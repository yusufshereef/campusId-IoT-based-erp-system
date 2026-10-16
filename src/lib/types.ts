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

export type Tab =
  "overview" | "attendance" | "classes" | "students" | "teachers";
export type Notice = { message: string; kind: "success" | "error" };
export type Notify = (message: string, kind?: Notice["kind"]) => void;
