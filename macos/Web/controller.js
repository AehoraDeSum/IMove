"use strict";

const $ = (id) => document.getElementById(id);
let token = "";
let working = false;
let liveTimer = null;
let deviceReady = false;
let routeMode = false;
let routeDraftPoints = [];
let routeLegSeconds = [];
let routeDraftPaths = [];
let routeDescriptions = [];
let routeVias = [];
let routeAddingVia = false;
let railCatalogue = [];
let routeActive = false;
let statusTimer = null;
let intervalDirty = false;

function updateMapMode() {
  $("mapMode").textContent = routeMode
    ? `Route drawing · ${routeDraftPoints.length} points selected`
    : "Pick a location on the map";
}

function setMapExpanded(expanded) {
  $("mapShell").classList.toggle("expanded", expanded);
  document.body.classList.toggle("map-open", expanded);
  $("mapExpand").textContent = expanded ? "Close ×" : "Full screen ↗";
  requestAnimationFrame(() => $("mapFrame").contentWindow?.postMessage({ type: "imove-resize" }, location.origin));
}

function note(message, error = false) {
  $("message").textContent = message;
  $("message").classList.toggle("error", error);
}

async function api(path, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);
  try {
    const response = await fetch(path, {
      ...options,
      cache: "no-store",
      signal: controller.signal,
      headers: { "X-IMove-Token": token, ...(options.headers || {}) }
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.message || "The operation could not be completed.");
    return result;
  } finally { clearTimeout(timeout); }
}

async function refreshStatus() {
  const result = await api("/api/status");
  deviceReady = result.ready && !result.busy;
  $("readiness").textContent = result.ready ? "iPhone connection ready" : "USB target must be prepared on the Mac";
  $("readiness").classList.toggle("ready", result.ready);
  $("lastSent").textContent = result.lastSent ? `Last sent: ${result.lastSent}` : "No location sent yet.";
  if (!intervalDirty) {
    const seconds = String(result.updateIntervalSeconds || 20);
    if (![...$("intervalSelect").options].some((option) => option.value === seconds)) {
      $("intervalSelect").add(new Option(`${seconds} ${seconds === 1 ? "second" : "seconds"}`, seconds));
    }
    $("intervalSelect").value = seconds;
  }
  $("refreshState").textContent = result.refreshing
    ? `The Mac refreshes the last location at most every ${result.updateIntervalSeconds} seconds.`
    : `Fixed location refresh off · route interval ${result.updateIntervalSeconds} seconds.`;
  if (Number.isFinite(result.lastUSBSetDurationMs)) {
    $("refreshState").textContent += ` Last successful USB command: ~${result.lastUSBSetDurationMs} ms.`;
  }
  $("stopRefresh").hidden = !result.refreshing;
  const match = result.lastSent.match(/^(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)$/);
  if (match) $("mapFrame").contentWindow?.postMessage({ type: "imove-last", latitude: Number(match[1]), longitude: Number(match[2]) }, location.origin);
  $("send").disabled = !result.ready || result.busy;
  $("current").disabled = !result.ready || result.busy;
  $("startLive").disabled = !result.ready || result.busy;
  $("clear").disabled = !result.ready || result.busy;
  document.querySelectorAll(".place-send").forEach((button) => { button.disabled = !deviceReady; });
  routeActive = Boolean(result.routeID);
  $("routeStatus").textContent = routeActive
    ? `Active route: ${result.routeName} · ${Math.round(result.routeProgress * 100)}% · segment ${result.routeSegmentIndex}/${result.routeSegmentCount}`
    : result.message.startsWith("Route completed") ? result.message : "No active route.";
  $("routeStop").hidden = !routeActive;
  document.querySelectorAll(".route-start").forEach((button) => { button.disabled = !deviceReady || routeActive; });
}

function renderRouteDraft() {
  const list = $("routeDraft");
  list.replaceChildren();
  if (!routeDraftPoints.length) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "No route points selected yet.";
    list.append(empty);
  }
  routeDraftPoints.forEach((point, index) => {
    const row = document.createElement("div");
    row.className = "route-point";
    row.textContent = `${index + 1}. ${point.latitude.toFixed(6)}, ${point.longitude.toFixed(6)}` +
      (index ? ` · ${routeDescriptions[index - 1] || "Hand-drawn segment"}` : "");
    list.append(row);
  });
  const legCount = Math.max(0, routeDraftPoints.length - 1);
  routeLegSeconds.length = legCount;
  for (let index = 0; index < legCount; index++) {
    if (!Number.isInteger(routeLegSeconds[index])) routeLegSeconds[index] = 300;
    if (!routeDraftPaths[index]) routeDraftPaths[index] = [routeDraftPoints[index], routeDraftPoints[index + 1]];
    if (!routeDescriptions[index]) routeDescriptions[index] = "Hand-drawn segment";
    if (!routeVias[index]) routeVias[index] = [];
  }
  routeDraftPaths.length = legCount;
  routeDescriptions.length = legCount;
  routeVias.length = legCount;
  const legSelect = $("editLeg");
  const selected = Number(legSelect.value);
  legSelect.replaceChildren();
  for (let index = 0; index < legCount; index++) legSelect.add(new Option(`${index + 1} → ${index + 2}`, String(index)));
  if (Number.isInteger(selected) && selected >= 0 && selected < legCount) legSelect.value = String(selected);
  renderRouteTiming();
  $("routeUndo").disabled = routeDraftPoints.length === 0;
  $("routeClear").disabled = routeDraftPoints.length === 0;
  $("routeSave").disabled = routeDraftPoints.length < 2;
  $("mapFrame").contentWindow?.postMessage({ type: "imove-route-points", points: routeDraftPoints,
    paths: routeDraftPaths }, location.origin);
  updateMapMode();
}

function appendPoint(point, path = null, description = "Hand-drawn segment", seconds = 300) {
  const previous = routeDraftPoints.at(-1);
  if (previous) {
    routeDraftPaths.push(path || [previous, point]);
    routeDescriptions.push(description);
    routeVias.push([]);
    routeLegSeconds.push(seconds);
  }
  routeDraftPoints.push(point);
}

function railLine() { return railCatalogue.find((line) => line.id === $("railLine").value); }

function renderRailStations() {
  const selected = $("railLine").value;
  $("railLine").replaceChildren();
  railCatalogue.forEach((line) => $("railLine").add(new Option(`${line.id} · ${line.name}`, line.id)));
  if (railCatalogue.some((line) => line.id === selected)) $("railLine").value = selected;
  const line = railLine();
  for (const id of ["railBoard", "railAlight"]) {
    const select = $(id);
    select.replaceChildren();
    line?.stations.forEach((station, index) => select.add(new Option(station.name, String(index))));
  }
  $("railAlight").value = "1";
}

function stationPoint(station) { return { latitude: station.latitude, longitude: station.longitude }; }

function meters(a, b) {
  return Math.hypot((a.latitude - b.latitude) * 111000,
    (a.longitude - b.longitude) * 111000 * Math.cos(a.latitude * Math.PI / 180));
}

async function walkToBoard() {
  const line = railLine();
  const station = line?.stations[Number($("railBoard").value)];
  if (!station) return note("Choose a line and boarding station first.", true);
  const end = stationPoint(station), start = routeDraftPoints.at(-1);
  if (!start) {
    appendPoint(end); renderRouteDraft(); note("Boarding station added as the starting point."); return;
  }
  if (meters(start, end) < 1) return note("The route is already at the boarding station.");
  try {
    const result = await api("/api/route/walking", { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ points: [start, end] }) });
    if (routeDraftPoints.at(-1) !== start) return note("The route changed; start the walking calculation again.", true);
    appendPoint(end, result.points, `Walk · ${station.name}`, Math.max(1, Math.min(86400, result.estimatedSeconds)));
    renderRouteDraft(); note("Walking segment to the boarding station added.");
  } catch (error) { note(error.message, true); }
}

function appendRail() {
  const line = railLine();
  const board = Number($("railBoard").value), alight = Number($("railAlight").value);
  if (!line || board === alight || !line.stations[board] || !line.stations[alight])
    return note("Choose different boarding and alighting stations.", true);
  const origin = stationPoint(line.stations[board]);
  const previous = routeDraftPoints.at(-1);
  if (previous && meters(previous, origin) > 400)
    return note("The boarding station is far away. Add a walking segment to it first.", true);
  if (!previous) appendPoint(origin);
  else if (meters(previous, origin) > 1)
    appendPoint(origin, [previous, origin], "Transfer · short walk (approximate)",
      Math.max(60, Math.round(meters(previous, origin) / 1.2)));
  const step = board < alight ? 1 : -1;
  for (let index = board; index !== alight; index += step) {
    const next = index + step;
    const startStation = line.stations[index], endStation = line.stations[next];
    const source = line.stations[Math.min(index, next)];
    const shape = source.pathToNext;
    if (!Array.isArray(shape) || shape.length < 2) return note("No path found for this line section.", true);
    const path = (step > 0 ? shape : [...shape].reverse()).map(([latitude, longitude]) => ({ latitude, longitude }));
    appendPoint(stationPoint(endStation), path,
      `${line.id} · ${startStation.name} → ${endStation.name}` +
      (source.geometryApproximate ? " · approximate path" : ""), line.id === "B1" ? 150 : 120);
  }
  $("routeMinutes").value = Math.max(Number($("routeMinutes").value) || 0,
    Math.ceil(routeLegSeconds.reduce((sum, value) => sum + value, 0) / 60));
  renderRouteDraft();
  $("mapFrame").contentWindow?.postMessage({ type: "imove-route-fit" }, location.origin);
  note(`${line.id} · ${Math.abs(alight - board)} station segments added. Review the durations.`);
}

async function calculateWalkingLeg() {
  const index = Number($("editLeg").value);
  if (!Number.isInteger(index) || !routeDraftPaths[index]) return note("Choose a route segment first.", true);
  const start = routeDraftPoints[index], end = routeDraftPoints[index + 1];
  try {
    const result = await api("/api/route/walking", { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ points: [routeDraftPoints[index], ...routeVias[index], routeDraftPoints[index + 1]] }) });
    if (routeDraftPoints[index] !== start || routeDraftPoints[index + 1] !== end)
      return note("The route changed; start the walking calculation again.", true);
    routeDraftPaths[index] = result.points;
    routeDescriptions[index] = "Walk · follows streets";
    routeLegSeconds[index] = Math.max(1, Math.min(86400, result.estimatedSeconds));
    routeAddingVia = false;
    $("addVia").textContent = "Add waypoints on map";
    renderRouteDraft(); note("Walking route calculated.");
  } catch (error) { note(error.message, true); }
}

function formatDuration(seconds) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return `${hours ? `${hours} h ` : ""}${minutes} min ${remainder} s`;
}

function renderRouteTiming() {
  const custom = $("routeTimingMode").value === "custom";
  $("routeTotalFields").hidden = custom;
  $("routeLegFields").hidden = !custom;
  const list = $("routeLegList");
  list.replaceChildren();
  if (custom) routeLegSeconds.forEach((duration, index) => {
    const row = document.createElement("div");
    row.className = "route-leg";
    const label = document.createElement("span");
    label.textContent = `${index + 1} → ${index + 2}`;
    row.append(label);
    for (const part of ["minutes", "seconds"]) {
      const input = document.createElement("input");
      input.type = "number";
      input.min = "0";
      input.step = "1";
      input.value = part === "minutes" ? Math.floor(duration / 60) : duration % 60;
      input.setAttribute("aria-label", `${part === "minutes" ? "Minutes" : "Seconds"} from ${index + 1} to ${index + 2}`);
      input.addEventListener("input", () => {
        const value = Number(input.value);
        const prior = routeLegSeconds[index];
        routeLegSeconds[index] = part === "minutes" ? value * 60 + prior % 60 : Math.floor(prior / 60) * 60 + value;
        updateRouteTotal();
      });
      row.append(input, document.createTextNode(part === "minutes" ? "dk" : "sn"));
    }
    list.append(row);
  });
  updateRouteTotal();
}

function updateRouteTotal() {
  const custom = $("routeTimingMode").value === "custom";
  const total = custom ? routeLegSeconds.reduce((sum, value) => sum + value, 0)
    : Number($("routeMinutes").value) * 60 + Number($("routeSeconds").value);
  $("routeTotalSummary").textContent = Number.isInteger(total) && total >= 0
    ? `Total duration: ${formatDuration(total)}` : "Enter valid minutes and seconds.";
}

async function loadRoutes() {
  const result = await api("/api/routes");
  const list = $("routesList");
  list.replaceChildren();
  if (!result.routes.length) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "No routes saved yet.";
    list.append(empty);
  }
  for (const route of result.routes) {
    const row = document.createElement("div");
    row.className = "place";
    const title = document.createElement("strong");
    title.textContent = route.name;
    const detail = document.createElement("span");
    detail.className = "muted";
    detail.textContent = `${route.points.length} points · ${route.timingMode === "custom" ? "custom" : "even"} timing · total ${formatDuration(route.totalDurationSeconds)}`;
    const actions = document.createElement("div");
    actions.className = "actions";
    const preview = document.createElement("button");
    preview.textContent = "Open on map";
    preview.addEventListener("click", () => {
      routeDraftPoints = route.points.map((point) => ({ latitude: Number(point.latitude), longitude: Number(point.longitude) }));
      routeDraftPaths = route.segmentPaths?.length ? route.segmentPaths :
        routeDraftPoints.slice(1).map((point, index) => [routeDraftPoints[index], point]);
      routeDescriptions = route.segmentDescriptions?.length ? [...route.segmentDescriptions] :
        routeDraftPaths.map(() => "Hand-drawn segment");
      routeVias = routeDraftPaths.map(() => []);
      routeLegSeconds = [...route.segmentDurationsSeconds];
      $("routeName").value = "";
      $("routeTimingMode").value = route.timingMode;
      $("routeMinutes").value = Math.floor(route.totalDurationSeconds / 60);
      $("routeSeconds").value = route.totalDurationSeconds % 60;
      routeMode = true;
      $("routeMode").textContent = "Finish drawing route";
      renderRouteDraft();
      $("mapFrame").contentWindow?.postMessage({ type: "imove-route-fit" }, location.origin);
      note("Route opened as a draft. Edit it and save it under a new name.");
    });
    const start = document.createElement("button");
    start.className = "primary route-start";
    start.textContent = "Start";
    start.disabled = !deviceReady || routeActive;
    start.addEventListener("click", async () => {
      if (liveTimer) stopLive("Live updates stopped.");
      try {
        const result = await api("/api/routes/start", {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: route.id })
        });
        note(result.message);
        await refreshStatus();
      } catch (error) { note(error.message, true); }
    });
    const remove = document.createElement("button");
    remove.textContent = "Delete";
    remove.addEventListener("click", async () => {
      if (!confirm(`Delete the route "${route.name}"?`)) return;
      try {
        const result = await api("/api/routes/delete", {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: route.id })
        });
        note(result.message);
        await loadRoutes();
      } catch (error) { note(error.message, true); }
    });
    actions.append(preview, start, remove);
    row.append(title, detail, actions);
    list.append(row);
  }
}

function renderQuickPlaces(places) {
  const quick = $("quickPlaces");
  quick.replaceChildren();
  const label = document.createElement("span");
  label.className = "quick-label";
  label.textContent = "SAVED PLACES";
  quick.append(label);
  if (!places.length) {
    const empty = document.createElement("span");
    empty.className = "quick-empty";
    empty.textContent = "Nothing saved yet.";
    quick.append(empty);
  }
  for (const place of places) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = place.name;
    button.addEventListener("click", () => {
      $("latitude").value = place.latitude;
      $("longitude").value = place.longitude;
      note(place.name + " selected. Press the send button to send it.");
    });
    quick.append(button);
  }
  const add = document.createElement("button");
  add.type = "button";
  add.textContent = "Add place +";
  add.addEventListener("click", () => {
    $("placesSection").scrollIntoView({ behavior: "smooth", block: "start" });
    $("placeName").focus();
  });
  quick.append(add);
}

async function loadPlaces() {
  const result = await api("/api/places");
  renderQuickPlaces(result.places);
  const list = $("placesList");
  list.replaceChildren();
  if (!result.places.length) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "No places saved yet.";
    list.append(empty);
    return;
  }
  for (const place of result.places) {
    const row = document.createElement("div");
    row.className = "place";
    const title = document.createElement("strong");
    title.textContent = place.name;
    const coordinates = document.createElement("span");
    coordinates.className = "muted";
    coordinates.textContent = `${place.latitude}, ${place.longitude}`;
    const actions = document.createElement("div");
    actions.className = "actions";
    const send = document.createElement("button");
    send.className = "primary place-send";
    send.textContent = "Send to iPhone";
    send.disabled = !deviceReady;
    send.addEventListener("click", () => {
      if (liveTimer) stopLive("Live updates stopped.");
      $("latitude").value = place.latitude;
      $("longitude").value = place.longitude;
      sendCoordinates(String(place.latitude), String(place.longitude));
    });
    const remove = document.createElement("button");
    remove.textContent = "Delete";
    remove.addEventListener("click", async () => {
      if (!confirm(`Delete "${place.name}"?`)) return;
      try {
        const result = await api("/api/places/delete", {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: place.id })
        });
        note(result.message);
        await loadPlaces();
      } catch (error) { note(error.message, true); }
    });
    actions.append(send, remove);
    row.append(title, coordinates, actions);
    list.append(row);
  }
}

async function connect() {
  token = $("code").value.trim().toLowerCase();
  try {
    await refreshStatus();
    if ($("remember").checked) localStorage.setItem("imove-pairing-code", token);
    else localStorage.removeItem("imove-pairing-code");
    $("pairing").hidden = true;
    $("controls").hidden = false;
    requestAnimationFrame(() => $("mapFrame").contentWindow?.postMessage({ type: "imove-resize" }, location.origin));
    note("Connected to the Mac.");
    await loadPlaces();
    await loadRoutes();
    try { railCatalogue = (await api("/api/transit")).lines; renderRailStations(); }
    catch (error) { note(`Could not read line data: ${error.message}`, true); }
    if (!statusTimer) statusTimer = setInterval(() => {
      if (!document.hidden) refreshStatus().catch(() => {});
    }, 5000);
  } catch (error) {
    note(error.message, true);
  }
}

async function sendCoordinates(latitude, longitude, renew = $("autoRenew").checked) {
  if (working) return;
  working = true;
  $("send").disabled = true;
  $("current").disabled = true;
  try {
    const result = await api("/api/location", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ latitude, longitude, renew })
    });
    note(result.message);
    await refreshStatus();
  } catch (error) {
    note(error.message, true);
  } finally {
    working = false;
  }
}

function currentPosition() {
  if (!navigator.geolocation) return Promise.reject(new Error("This browser cannot provide a location."));
  return new Promise((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      maximumAge: 0,
      timeout: 20000
    });
  });
}

async function sendCurrent(live = false) {
  try {
    note("Getting the device's current location…");
    const result = await currentPosition();
    const latitude = result.coords.latitude.toFixed(6);
    const longitude = result.coords.longitude.toFixed(6);
    $("latitude").value = latitude;
    $("longitude").value = longitude;
    await sendCoordinates(latitude, longitude, live ? false : $("autoRenew").checked);
    if (liveTimer) note(`Location sent · accuracy about ${Math.round(result.coords.accuracy)} m · next attempt in 5 minutes.`);
  } catch (error) {
    note(error.message || "Could not get a location. Check the device's location permission.", true);
  }
}

function stopLive(message = "5-minute updates stopped.") {
  if (liveTimer) clearInterval(liveTimer);
  liveTimer = null;
  $("startLive").hidden = false;
  $("stopLive").hidden = true;
  note(message);
}

$("connect").addEventListener("click", connect);
$("code").addEventListener("keydown", (event) => { if (event.key === "Enter") connect(); });
$("send").addEventListener("click", () => sendCoordinates($("latitude").value, $("longitude").value));
$("current").addEventListener("click", () => sendCurrent());
$("intervalSelect").addEventListener("change", () => { intervalDirty = true; });
$("saveInterval").addEventListener("click", async () => {
  try {
    const seconds = Number($("intervalSelect").value);
    const result = await api("/api/settings/interval", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ seconds })
    });
    intervalDirty = false;
    note(result.message);
    await refreshStatus();
  } catch (error) { note(error.message, true); }
});
$("stopRefresh").addEventListener("click", async () => {
  try {
    const result = await api("/api/refresh/stop", { method: "POST" });
    $("autoRenew").checked = false;
    note(result.message);
    await refreshStatus();
  } catch (error) { note(error.message, true); }
});
$("mapFrame").addEventListener("load", () => {
  $("mapFrame").contentWindow?.postMessage({ type: "imove-resize" }, location.origin);
  renderRouteDraft();
  if (token) refreshStatus().catch(() => {});
});
$("mapExpand").addEventListener("click", () => setMapExpanded(!$("mapShell").classList.contains("expanded")));
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && $("mapShell").classList.contains("expanded")) setMapExpanded(false);
});
window.addEventListener("message", (event) => {
  if (event.origin !== location.origin || event.source !== $("mapFrame").contentWindow || event.data?.type !== "imove-pick") return;
  const { latitude, longitude } = event.data;
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return;
  if (routeMode) {
    if (routeAddingVia) {
      const index = Number($("editLeg").value);
      if (!routeDraftPaths[index]) return note("Choose a segment to edit first.", true);
      routeVias[index].push({ latitude, longitude });
      routeDraftPaths[index] = [routeDraftPoints[index], ...routeVias[index], routeDraftPoints[index + 1]];
      routeDescriptions[index] = "Hand-edited segment";
      renderRouteDraft();
      return note(`Waypoint added to segment ${index + 1}.`);
    }
    appendPoint({ latitude, longitude });
    renderRouteDraft();
    note(`Route point ${routeDraftPoints.length} added.`);
    return;
  }
  $("latitude").value = latitude.toFixed(6);
  $("longitude").value = longitude.toFixed(6);
  note("The map point was copied into the coordinate fields.");
  if ($("mapShell").classList.contains("expanded")) setMapExpanded(false);
});
$("routeMode").addEventListener("click", () => {
  routeMode = !routeMode;
  if (!routeMode) { routeAddingVia = false; $("addVia").textContent = "Add waypoints on map"; }
  $("routeMode").textContent = routeMode ? "Finish drawing route" : "Start drawing route";
  updateMapMode();
  note(routeMode ? "Tap the map to add route points in order." : "The map is back to single-location picking.");
});
$("railLine").addEventListener("change", renderRailStations);
$("railWalk").addEventListener("click", walkToBoard);
$("railAdd").addEventListener("click", appendRail);
$("addVia").addEventListener("click", () => {
  if (!routeDraftPaths.length) return note("Add a route segment first.", true);
  routeAddingVia = !routeAddingVia;
  routeMode = true;
  $("routeMode").textContent = "Finish drawing route";
  $("addVia").textContent = routeAddingVia ? "Finish adding waypoints" : "Add waypoints on map";
  updateMapMode();
});
$("walkLeg").addEventListener("click", calculateWalkingLeg);
$("routeUndo").addEventListener("click", () => {
  routeDraftPoints.pop(); routeDraftPaths.pop(); routeDescriptions.pop(); routeVias.pop(); routeLegSeconds.pop();
  renderRouteDraft();
});
$("routeClear").addEventListener("click", () => {
  routeDraftPoints = []; routeDraftPaths = []; routeDescriptions = []; routeVias = []; routeLegSeconds = [];
  routeAddingVia = false; $("addVia").textContent = "Add waypoints on map"; renderRouteDraft();
});
$("routeTimingMode").addEventListener("change", renderRouteTiming);
$("routeMinutes").addEventListener("input", updateRouteTotal);
$("routeSeconds").addEventListener("input", updateRouteTotal);
$("routeRefresh").addEventListener("click", async () => {
  try { await loadRoutes(); note("Routes refreshed."); }
  catch (error) { note(error.message, true); }
});
$("routeSave").addEventListener("click", async () => {
  if (routeDraftPoints.length < 2) return note("Choose at least two route points.", true);
  const mode = $("routeTimingMode").value;
  const minutes = Number($("routeMinutes").value);
  const seconds = Number($("routeSeconds").value);
  const total = minutes * 60 + seconds;
  if (mode === "equal" && (!Number.isSafeInteger(minutes) || minutes < 0 || !Number.isInteger(seconds) || seconds < 0 || seconds > 59 || total < routeDraftPoints.length - 1))
    return note("The total duration must be valid and each segment must last at least 1 second.", true);
  const count = routeDraftPoints.length - 1;
  const durations = mode === "equal" ? Array.from({ length: count }, (_, index) => Math.floor(total / count) + (index < total % count ? 1 : 0)) : [...routeLegSeconds];
  if (durations.length !== count || durations.some((value) => !Number.isInteger(value) || value < 1 || value > 86400))
    return note("Each segment must last between 1 second and 24 hours.", true);
  try {
    const result = await api("/api/routes", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: $("routeName").value, timingMode: mode, segmentDurationsSeconds: durations,
        points: routeDraftPoints, segmentPaths: routeDraftPaths, segmentDescriptions: routeDescriptions })
    });
    routeDraftPoints = [];
    routeDraftPaths = []; routeDescriptions = []; routeVias = [];
    routeLegSeconds = [];
    routeMode = false;
    $("routeMode").textContent = "Start drawing route";
    $("routeName").value = "";
    renderRouteDraft();
    note(result.message);
    await loadRoutes();
  } catch (error) { note(error.message, true); }
});
$("routeStop").addEventListener("click", async () => {
  try {
    const result = await api("/api/routes/stop", { method: "POST" });
    note(result.message);
    await refreshStatus();
  } catch (error) { note(error.message, true); }
});
$("refreshPlaces").addEventListener("click", async () => {
  try { await loadPlaces(); note("Saved places refreshed."); }
  catch (error) { note(error.message, true); }
});
$("savePlace").addEventListener("click", async () => {
  try {
    const result = await api("/api/places", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: $("placeName").value, latitude: $("latitude").value, longitude: $("longitude").value })
    });
    $("placeName").value = "";
    note(result.message);
    await loadPlaces();
  } catch (error) { note(error.message, true); }
});
$("startLive").addEventListener("click", () => {
  if (document.hidden) return note("Keep the page open for updates.", true);
  if (liveTimer) return;
  liveTimer = setInterval(() => sendCurrent(true), 300000);
  $("startLive").hidden = true;
  $("stopLive").hidden = false;
  sendCurrent(true);
});
$("stopLive").addEventListener("click", () => stopLive());
$("clear").addEventListener("click", async () => {
  if (!confirm("Remove the simulated location? The iPhone may return to its real location.")) return;
  if (liveTimer) stopLive("Live updates stopped.");
  try {
    const result = await api("/api/clear", { method: "POST" });
    note(result.message);
    await refreshStatus();
  } catch (error) { note(error.message, true); }
});
document.addEventListener("visibilitychange", () => {
  if (document.hidden && liveTimer) stopLive("5-minute updates stopped because the page went to the background.");
  if (!document.hidden && token) refreshStatus().catch(() => {});
});

renderRouteDraft();

const saved = localStorage.getItem("imove-pairing-code");
if (saved) {
  $("code").value = saved;
  connect();
}
