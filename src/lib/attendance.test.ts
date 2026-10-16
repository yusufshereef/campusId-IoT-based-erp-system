import { describe, expect, it } from "vitest";
import {
  AttendanceRequestError,
  createAttendanceEventId,
  saveAttendance,
  summarizeAttendance,
  type AttendanceRecord,
} from "./attendance";

const record = (
  student_id: string,
  status: AttendanceRecord["status"],
): AttendanceRecord => ({
  id: `record-${student_id}`,
  class_id: "class-1",
  student_id,
  attendance_date: "2026-10-16",
  status,
  recorded_by_user_id: "teacher-1",
  client_event_id: null,
  created_at: "2026-10-16T00:00:00Z",
  updated_at: "2026-10-16T00:00:00Z",
});

describe("attendance service helpers", () => {
  it("does not count records outside the selected roster", () => {
    expect(
      summarizeAttendance(["student-1"], [record("student-2", "present")]),
    ).toEqual({
      present: 0,
      absent: 0,
      late: 0,
      excused: 0,
      unmarked: 1,
    });
  });

  it("treats correction transport failures as unknown outcomes", async () => {
    const client = {
      from: () => ({
        update: () => ({
          eq: () => ({
            select: () => ({
              single: async () => {
                throw new Error("response lost");
              },
            }),
          }),
        }),
      }),
    } as never;
    await expect(
      saveAttendance(client, {
        id: "record-1",
        classId: "class-1",
        studentId: "student-1",
        attendanceDate: "2026-10-16",
        status: "late",
        userId: "teacher-1",
      }),
    ).rejects.toMatchObject({
      outcome: "unknown",
      name: "AttendanceRequestError",
    });
  });

  it("updates only status when correcting a record", async () => {
    let update: unknown;
    const client = {
      from: () => ({
        update: (values: unknown) => {
          update = values;
          return {
            eq: () => ({
              select: () => ({
                single: async () => ({
                  data: record("student-1", "late"),
                  error: null,
                }),
              }),
            }),
          };
        },
      }),
    } as never;
    await saveAttendance(client, {
      id: "record-1",
      classId: "class-1",
      studentId: "student-1",
      attendanceDate: "2026-10-16",
      status: "late",
      userId: "teacher-1",
    });
    expect(update).toEqual({ status: "late" });
  });
  it("counts marked and unmarked students by status", () => {
    expect(
      summarizeAttendance(
        ["student-1", "student-2", "student-3", "student-4", "student-5"],
        [
          record("student-1", "present"),
          record("student-2", "late"),
          record("student-3", "excused"),
          record("student-4", "absent"),
        ],
      ),
    ).toEqual({
      present: 1,
      late: 1,
      excused: 1,
      absent: 1,
      unmarked: 1,
    });
  });

  it("preserves the database code needed to handle concurrent duplicates", () => {
    const error = new AttendanceRequestError("duplicate", "23505");
    expect(error.code).toBe("23505");
    expect(error.name).toBe("AttendanceRequestError");
  });

  it("creates a stable event ID that can be passed back for a retry", async () => {
    const eventId = createAttendanceEventId();
    const requests: Record<string, unknown>[] = [];
    const builder = {
      insert(values: Record<string, unknown>) {
        requests.push(values);
        return this;
      },
      select() {
        return this;
      },
      single: async () => ({
        data: record("student-1", "present"),
        error: null,
      }),
    };
    const client = { from: () => builder } as never;

    await saveAttendance(client, {
      classId: "class-1",
      studentId: "student-1",
      attendanceDate: "2026-10-16",
      status: "present",
      userId: "teacher-1",
      clientEventId: eventId,
    });
    await saveAttendance(client, {
      classId: "class-1",
      studentId: "student-1",
      attendanceDate: "2026-10-16",
      status: "present",
      userId: "teacher-1",
      clientEventId: eventId,
    });

    expect(requests).toHaveLength(2);
    expect(requests[0].client_event_id).toBe(eventId);
    expect(requests[1].client_event_id).toBe(eventId);
  });

  it("marks thrown transport failures as unconfirmed and preserves the event ID", async () => {
    const eventId = createAttendanceEventId();
    const client = {
      from: () => ({
        insert: () => ({
          select: () => ({
            single: async () => {
              throw new Error("network timeout");
            },
          }),
        }),
      }),
    } as never;

    await expect(
      saveAttendance(client, {
        classId: "class-1",
        studentId: "student-1",
        attendanceDate: "2026-10-16",
        status: "present",
        userId: "teacher-1",
        clientEventId: eventId,
      }),
    ).rejects.toMatchObject({
      outcome: "unknown",
      clientEventId: eventId,
      message: "Attendance save could not be confirmed: network timeout",
    });
  });

  it("classifies duplicate responses as a confirmed database rejection", async () => {
    const client = {
      from: () => ({
        insert: () => ({
          select: () => ({
            single: async () => ({
              data: null,
              error: { code: "23505", message: "duplicate key" },
            }),
          }),
        }),
      }),
    } as never;

    await expect(
      saveAttendance(client, {
        classId: "class-1",
        studentId: "student-1",
        attendanceDate: "2026-10-16",
        status: "present",
        userId: "teacher-1",
        clientEventId: "event-1",
      }),
    ).rejects.toMatchObject({
      code: "23505",
      outcome: "rejected",
      clientEventId: "event-1",
    });
  });
});
