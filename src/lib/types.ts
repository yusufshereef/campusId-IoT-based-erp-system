export type CampusClass = {
  id: string;
  name: string;
  section: string;
  academic_year: string | null;
};

export type Person = {
  id: string;
  full_name: string;
  role: "student" | "teacher";
  roll_number: string | null;
  employee_id: string | null;
  class_id: string | null;
  fingerprint_status: string;
  active: boolean;
  classes?: CampusClass | null;
};

export type Device = {
  id: string;
  device_code: string;
  display_name: string;
  last_seen_at: string | null;
  firmware_version: string | null;
  sensor_ready: boolean;
  pending_event_count: number;
};

export type EnrollmentStatus = {
  person_id: string;
  device_code: string | null;
  display_name: string | null;
  slot_id: number | null;
  enrollment_status: string;
  command_id: string | null;
  command_status: string | null;
  error_message: string | null;
};

export type Tab =
  "overview" | "attendance" | "classes" | "students" | "teachers";
export type Notice = {
  message: string;
  kind: "success" | "error" | "warning" | "info";
};
export type Notify = (message: string, kind?: Notice["kind"]) => void;
