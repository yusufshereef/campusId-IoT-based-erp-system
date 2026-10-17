import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Overview } from "./Overview";
import type { CampusClass, Device, EnrollmentStatus, Person } from "../lib/types";

const people: Person[] = [
  {
    id: "student-1",
    full_name: "Asha",
    role: "student",
    roll_number: "26cs001",
    employee_id: null,
    class_id: "class-1",
    fingerprint_status: "enrolled",
    active: true,
  },
  {
    id: "student-2",
    full_name: "Bilal",
    role: "student",
    roll_number: "26cs002",
    employee_id: null,
    class_id: "class-1",
    fingerprint_status: "not_enrolled",
    active: true,
  },
];

const campusClasses: CampusClass[] = [
  { id: "class-1", name: "CSE", section: "A", academic_year: "2026-27" },
];

const device: Device = {
  id: "device-1",
  device_code: "terminal-01",
  display_name: "CampusID Terminal 01",
  last_seen_at: "2026-10-17T12:00:00.000Z",
  firmware_version: "1.0.0",
  sensor_ready: true,
  pending_event_count: 0,
};

function renderOverview(overrides: Partial<Parameters<typeof Overview>[0]> = {}) {
  return renderToStaticMarkup(
    <Overview
      classes={campusClasses}
      students={people}
      teachers={[]}
      connected
      loading={false}
      isAdmin
      device={device}
      deviceError={null}
      now={Date.parse("2026-10-17T12:00:08.000Z")}
      enrollmentStatuses={{
        "student-1": {
          person_id: "student-1",
          device_code: "terminal-01",
          display_name: "CampusID Terminal 01",
          slot_id: 1,
          enrollment_status: "enrolled",
          command_id: null,
          command_status: "completed",
          error_message: null,
        },
        "student-2": {
          person_id: "student-2",
          device_code: null,
          display_name: null,
          slot_id: null,
          enrollment_status: "not_enrolled",
          command_id: null,
          command_status: null,
          error_message: null,
        },
      }}
      enrollmentStatusAvailable
      {...overrides}
    />,
  );
}

describe("operational overview", () => {
  it("removes the hero and renders real campus and terminal data", () => {
    const markup = renderOverview();
    expect(markup).not.toContain("Every presence.");
    expect(markup).not.toContain("Open attendance");
    expect(markup).toContain("SYSTEM STATUS");
    expect(markup).toContain("Online");
    expect(markup).toContain("Ready");
    expect(markup).toContain("8s ago");
    expect(markup).toContain("Students");
    expect(markup).toContain(">2<");
    expect(markup).toContain("Teachers");
    expect(markup).toContain("Classes");
    expect(markup).toContain("Enrolled fingerprints");
    expect(markup).not.toContain("Planned");
  });

  it("uses backend enrollment statuses and omits unavailable cleanup totals", () => {
    const rows: EnrollmentStatus[] = [
      {
        person_id: "student-1",
        device_code: "terminal-01",
        display_name: "CampusID Terminal 01",
        slot_id: 1,
        enrollment_status: "enrolled",
        command_id: null,
        command_status: "completed",
        error_message: null,
      },
      {
        person_id: "student-2",
        device_code: "terminal-01",
        display_name: "CampusID Terminal 01",
        slot_id: null,
        enrollment_status: "in_progress",
        command_id: "command-1",
        command_status: "processing",
        error_message: null,
      },
    ];
    const markup = renderOverview({
      enrollmentStatuses: Object.fromEntries(rows.map((row) => [row.person_id, row])),
    });
    expect(markup).toContain("Enrolled fingerprints");
    expect(markup.match(/Enrolled fingerprints<\/small><\/div><strong>1<\/strong>/)).not.toBeNull();
    expect(markup).toContain("Pending enrollment");
    expect(markup).toContain("Fingerprint removal");
    expect(markup).not.toContain("Pending cleanup");
    expect(markup).not.toContain("Needs attention</h2>");
    expect(markup).toContain("All systems operational");
  });

  it("does not invent biometric counts and only shows attention when warranted", () => {
    const unavailable = renderOverview({ enrollmentStatusAvailable: false });
    expect(unavailable).toContain("aria-busy=\"true\"");
    expect(unavailable).toContain("—");

    const offline = renderOverview({
      device: { ...device, sensor_ready: false, last_seen_at: null },
    });
    expect(offline).toContain("Needs attention");
    expect(offline).toContain("Fingerprint terminal is offline.");
    expect(offline).toContain("Fingerprint sensor is unavailable.");
    expect(offline).not.toContain("All systems operational");
  });
});
