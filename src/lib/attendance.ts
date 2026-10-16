import type { SupabaseClient } from "@supabase/supabase-js";
import { databaseError } from "./admin";

export type AttendanceStatus = "present" | "absent" | "late" | "excused";

export type AttendanceRecord = {
  id: string;
  class_id: string;
  student_id: string;
  attendance_date: string;
  status: AttendanceStatus;
  recorded_by_user_id: string;
  client_event_id: string | null;
  created_at: string;
  updated_at: string;
};

export type AttendanceSummary = {
  present: number;
  late: number;
  excused: number;
  absent: number;
  unmarked: number;
};

type AttendanceClient = SupabaseClient;
export type AttendanceWriteOutcome = "rejected" | "unknown";

export class AttendanceRequestError extends Error {
  constructor(
    message: string,
    readonly code?: string,
    readonly outcome: AttendanceWriteOutcome = "rejected",
    readonly clientEventId?: string,
  ) {
    super(message);
    this.name = "AttendanceRequestError";
  }
}

function requestError(
  error: { code?: string; message: string },
  clientEventId?: string,
) {
  const outcome =
    error.code && /^[2354]\d{4}$/.test(error.code) ? "rejected" : "unknown";
  return new AttendanceRequestError(
    databaseError(error),
    error.code,
    outcome,
    clientEventId,
  );
}

export function createAttendanceEventId() {
  return crypto.randomUUID();
}

export function summarizeAttendance(
  studentIds: string[],
  records: AttendanceRecord[],
): AttendanceSummary {
  const summary: AttendanceSummary = {
    present: 0,
    late: 0,
    excused: 0,
    absent: 0,
    unmarked: 0,
  };
  const statuses = new Map(
    records.map((record) => [record.student_id, record.status]),
  );
  for (const studentId of studentIds) {
    const status = statuses.get(studentId);
    if (status) summary[status] += 1;
    else summary.unmarked += 1;
  }
  return summary;
}

export async function loadAttendance(
  client: AttendanceClient,
  classId: string,
  attendanceDate: string,
) {
  const { data, error } = await client
    .from("attendance_records")
    .select(
      "id,class_id,student_id,attendance_date,status,recorded_by_user_id,client_event_id,created_at,updated_at",
    )
    .eq("class_id", classId)
    .eq("attendance_date", attendanceDate)
    .order("created_at");
  if (error) throw requestError(error);
  return (data || []) as AttendanceRecord[];
}

export async function saveAttendance(
  client: AttendanceClient,
  input: {
    id?: string;
    classId: string;
    studentId: string;
    attendanceDate: string;
    status: AttendanceStatus;
    userId: string;
    clientEventId?: string;
  },
) {
  // Both inserts and corrections can commit before a transport response fails.
  const clientEventId = input.id
    ? undefined
    : input.clientEventId || createAttendanceEventId();
  try {
    if (input.id) {
      const { data, error } = await client
        .from("attendance_records")
        .update({ status: input.status })
        .eq("id", input.id)
        .select(
          "id,class_id,student_id,attendance_date,status,recorded_by_user_id,client_event_id,created_at,updated_at",
        )
        .single();
      if (error) throw requestError(error);
      return data as AttendanceRecord;
    }
    const { data, error } = await client
      .from("attendance_records")
      .insert({
        class_id: input.classId,
        student_id: input.studentId,
        attendance_date: input.attendanceDate,
        status: input.status,
        recorded_by_user_id: input.userId,
        client_event_id: clientEventId,
      })
      .select(
        "id,class_id,student_id,attendance_date,status,recorded_by_user_id,client_event_id,created_at,updated_at",
      )
      .single();
    if (error) throw requestError(error, clientEventId);
    return data as AttendanceRecord;
  } catch (error) {
    if (error instanceof AttendanceRequestError) throw error;
    throw new AttendanceRequestError(
      error instanceof Error
        ? `Attendance save could not be confirmed: ${error.message}`
        : "Attendance save could not be confirmed. Check your connection.",
      undefined,
      "unknown",
      clientEventId,
    );
  }
}
