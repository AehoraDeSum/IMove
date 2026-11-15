"use strict";

const code = document.getElementById("code");
const status = document.getElementById("status");
const start = document.getElementById("start");
const stop = document.getElementById("stop");
let timer = null;
let pending = false;
let acquiring = false;
let generation = 0;

function halt(message) {
  generation += 1;
  if (timer) clearInterval(timer);
  timer = null;
  acquiring = false;
  start.disabled = false;
  stop.disabled = true;
  if (message) status.textContent = message;
}

async function submit(position) {
  if (!timer || pending) return;
  pending = true;
  try {
    const response = await fetch("/api/device-location", {
      method: "POST", cache: "no-store",
      headers: { "Content-Type": "application/json", "X-IMove-Token": code.value.trim() },
      body: JSON.stringify({
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        horizontalAccuracy: position.coords.accuracy,
        timestamp: position.timestamp / 1000,
        source: "safari"
      })
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.message || "The Mac did not respond.");
    const measured = new Date(position.timestamp).toLocaleTimeString("en-US");
    status.textContent = `${result.verification.message}\n\nReading: ${position.coords.latitude.toFixed(6)}, ${position.coords.longitude.toFixed(6)}\nAccuracy: about ${Math.round(position.coords.accuracy)} m · Time: ${measured}`;
  } catch (error) { status.textContent = `Could not send report: ${error.message}`; }
  finally { pending = false; }
}

function measure() {
  if (document.hidden) return halt("Safari went to the background; reading stopped. Start again.");
  if (acquiring || pending) return;
  acquiring = true;
  const currentGeneration = generation;
  status.textContent = "Measuring iPhone location…";
  navigator.geolocation.getCurrentPosition((position) => {
    if (currentGeneration !== generation || !timer) return;
    acquiring = false;
    submit(position);
  }, (firstError) => {
    if (currentGeneration !== generation || !timer) return;
    if (firstError.code === 1) {
      acquiring = false;
      status.textContent = "Safari location permission denied (code 1). Check Settings > Privacy & Security > Location Services > Safari Websites.";
      return;
    }
    status.textContent = `Could not get a high-accuracy reading (code ${firstError.code}: ${firstError.message}). Trying Wi-Fi/network location…`;
    navigator.geolocation.getCurrentPosition((position) => {
      if (currentGeneration !== generation || !timer) return;
      acquiring = false;
      submit(position);
    }, (fallbackError) => {
      if (currentGeneration !== generation || !timer) return;
      acquiring = false;
      status.textContent = `Could not read the iPhone location. First attempt: ${firstError.message} (code ${firstError.code}); Wi-Fi/network attempt: ${fallbackError.message} (code ${fallbackError.code}). Apart from the Safari permission, check whether the blue dot appears in Apple Maps.`;
    }, { enableHighAccuracy: false, maximumAge: 30_000, timeout: 20_000 });
  }, { enableHighAccuracy: true, maximumAge: 0, timeout: 20_000 });
}

start.addEventListener("click", () => {
  if (!/iPhone/.test(navigator.userAgent)) {
    status.textContent = "Open this page in Safari on the iPhone whose location you want to check.";
    return;
  }
  if (!/^[0-9a-fA-F]{32}$/.test(code.value.trim())) {
    status.textContent = "Enter the 32-character pairing code from the Mac.";
    return;
  }
  if (!navigator.geolocation) return halt("This version of Safari does not support reading location.");
  generation += 1;
  start.disabled = true;
  stop.disabled = false;
  status.textContent = "Waiting for iPhone location permission and the first reading…";
  timer = setInterval(measure, 10_000);
  measure();
});
stop.addEventListener("click", () => halt("Reading stopped."));
document.addEventListener("visibilitychange", () => {
  if (document.hidden && timer) halt("Safari went to the background; reading stopped. Start again.");
});
