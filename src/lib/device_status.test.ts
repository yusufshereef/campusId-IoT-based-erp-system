import { describe, expect, it } from "vitest";
import { deviceStatus, formatLastSeen, isDeviceOnline } from "./device_status";

describe("device status", () => {
  const now = Date.parse("2026-10-16T12:00:00.000Z");

  it("treats a recent heartbeat as online", () => {
    expect(isDeviceOnline("2026-10-16T11:59:30.000Z", now)).toBe(true);
    expect(
      deviceStatus(
        {
          id: "1",
          device_code: "campusid-terminal-01",
          display_name: "CampusID Terminal 01",
          last_seen_at: "2026-10-16T11:59:30.000Z",
          firmware_version: "0.1.0",
          sensor_ready: true,
          pending_event_count: 0,
        },
        now,
      ),
    ).toBe(true);
  });

  it("treats a stale or missing heartbeat as offline", () => {
    expect(isDeviceOnline("2026-10-16T11:59:14.000Z", now)).toBe(false);
    expect(isDeviceOnline(null, now)).toBe(false);
  });

  it("formats recent heartbeat age compactly", () => {
    expect(formatLastSeen("2026-10-16T11:59:58.000Z", now)).toBe("Just now");
    expect(formatLastSeen("2026-10-16T11:58:00.000Z", now)).toBe("2m ago");
    expect(formatLastSeen(null, now)).toBe("Never");
  });
});
