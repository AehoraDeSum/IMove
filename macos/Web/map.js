"use strict";

const parameters = new URLSearchParams(location.hash.replace(/^#/, ""));
const valid = (latitude, longitude) => Number.isFinite(latitude) && Number.isFinite(longitude) &&
  Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180;
const initialLatitude = Number(parameters.get("latitude"));
const initialLongitude = Number(parameters.get("longitude"));
const initial = parameters.has("latitude") && parameters.has("longitude") && valid(initialLatitude, initialLongitude)
  ? [initialLatitude, initialLongitude] : [41.0082, 28.9784];
const map = L.map("map", { zoomControl: false, tap: true }).setView(initial, 13);
L.control.zoom({ position: "bottomright" }).addTo(map);
L.control.scale({ position: "bottomleft", imperial: false }).addTo(map);
L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19,
  attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>'
}).addTo(map);
document.getElementById("styleToggle").addEventListener("click", () => {
  const dark = document.body.classList.toggle("dark-map");
  document.getElementById("styleToggle").textContent = dark ? "Light map" : "Dark map";
});

let pickedMarker = null;
let lastMarker = null;
let currentMarker = null;
let centeredOnLast = false;
let routeLayer = null;
let displayedRoutePoints = [];
function marker(latitude, longitude, color, label) {
  return L.circleMarker([latitude, longitude], {
    radius: 9, color: "white", weight: 3, fillColor: color, fillOpacity: 1
  }).bindTooltip(label);
}
function showLast(latitude, longitude) {
  if (!valid(latitude, longitude)) return;
  if (lastMarker) map.removeLayer(lastMarker);
  lastMarker = marker(latitude, longitude, "#2e76c3", "Last sent coordinate").addTo(map);
  if (!centeredOnLast && !parameters.has("latitude")) {
    map.setView([latitude, longitude], 12);
    centeredOnLast = true;
  }
}

map.on("click", (event) => {
  const latitude = Number(event.latlng.lat.toFixed(6));
  const longitude = Number(event.latlng.lng.toFixed(6));
  if (!valid(latitude, longitude)) return;
  if (pickedMarker) map.removeLayer(pickedMarker);
  pickedMarker = marker(latitude, longitude, "#4ae083", "Selected point").addTo(map);
  document.getElementById("hint").textContent = `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
  if (parameters.get("native") === "1") {
    location.href = `imove-pick://point?latitude=${latitude}&longitude=${longitude}`;
  } else if (window.parent !== window) {
    window.parent.postMessage({ type: "imove-pick", latitude, longitude }, location.origin);
  }
});

window.addEventListener("message", (event) => {
  if (event.origin !== location.origin) return;
  if (event.data?.type === "imove-resize") { map.invalidateSize(); return; }
  if (event.data?.type === "imove-route-points") {
    if (routeLayer) map.removeLayer(routeLayer);
    const points = Array.isArray(event.data.points) ? event.data.points.filter((point) =>
      valid(Number(point.latitude), Number(point.longitude))) : [];
    displayedRoutePoints = points;
    routeLayer = L.layerGroup();
    const paths = Array.isArray(event.data.paths) && event.data.paths.length === points.length - 1
      ? event.data.paths.flatMap((path) => Array.isArray(path) ? path : []) : points;
    if (paths.length >= 2) {
      L.polyline(paths.map((point) => [point.latitude, point.longitude]),
        { color: "#4ae083", weight: 4 }).addTo(routeLayer);
    }
    const markerStep = Math.max(1, Math.ceil(points.length / 100));
    points.forEach((point, index) => {
      if (index !== 0 && index !== points.length - 1 && index % markerStep !== 0) return;
      marker(point.latitude, point.longitude, "#4ae083", `Route point ${index + 1}`).addTo(routeLayer);
    });
    routeLayer.addTo(map);
    return;
  }
  if (event.data?.type === "imove-route-fit" && displayedRoutePoints.length >= 2) {
    map.fitBounds(displayedRoutePoints.map((point) => [point.latitude, point.longitude]), { padding: [25, 25] });
    return;
  }
  if (event.data?.type === "imove-route-view" &&
      valid(Number(event.data.latitude), Number(event.data.longitude))) {
    map.setView([Number(event.data.latitude), Number(event.data.longitude)], 12);
    return;
  }
  if (event.data?.type !== "imove-last") return;
  showLast(Number(event.data.latitude), Number(event.data.longitude));
});
if (parameters.has("lastLatitude") && parameters.has("lastLongitude")) {
  showLast(Number(parameters.get("lastLatitude")), Number(parameters.get("lastLongitude")));
}
if (parameters.has("currentLatitude") && parameters.has("currentLongitude")) {
  const latitude = Number(parameters.get("currentLatitude"));
  const longitude = Number(parameters.get("currentLongitude"));
  if (valid(latitude, longitude)) {
    currentMarker = marker(latitude, longitude, "#238451", "This phone's current location").addTo(map);
  }
}
