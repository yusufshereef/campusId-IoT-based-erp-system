import type { Device } from "./types";

export const DEVICE_OFFLINE_THRESHOLD_MS = 45_000;
export type DeviceReadiness = "not_integrated" | "connected" | "offline";

export function isDeviceOnline(
  lastSeenAt: string | null,
  now = Date.now(),
  thresholdMs = DEVICE_OFFLINE_THRESHOLD_MS,
) {
  if (!lastSeenAt) return false;
  const timestamp = Date.parse(lastSeenAt);
  return (
    Number.isFinite(timestamp) &&
    timestamp <= now &&
    now - timestamp <= thresholdMs
  );
}

export function deviceStatus(device: Device | null, now = Date.now()) {
  return Boolean(device && isDeviceOnline(device.last_seen_at, now));
}

export function deviceReadiness(
  device: Device | null,
  now = Date.now(),
): DeviceReadiness {
  if (!device) return "not_integrated";
  return deviceStatus(device, now) ? "connected" : "offline";
}

export function formatLastSeen(lastSeenAt: string | null, now = Date.now()) {
  if (!lastSeenAt) return "Never";
  const timestamp = Date.parse(lastSeenAt);
  if (!Number.isFinite(timestamp)) return "Unavailable";
  const seconds = Math.max(0, Math.round((now - timestamp) / 1000));
  if (seconds < 5) return "Just now";
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  return new Date(timestamp).toLocaleString();
}
