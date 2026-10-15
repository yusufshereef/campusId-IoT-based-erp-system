export type DatabaseError = {
  code?: string;
  message: string;
};

export type PersonRole = "student" | "teacher";

export function databaseError(error: DatabaseError | null) {
  if (!error) return "";
  if (error.code === "23505") {
    return "A record with the same class, roll number, or employee ID already exists.";
  }
  if (error.code === "23503") {
    return "The selected class no longer exists. Refresh the page and try again.";
  }
  if (error.code === "23514") {
    return "The submitted values do not satisfy the database rules.";
  }
  if (error.code === "42883" || error.code === "PGRST202") {
    return "Teacher registration is not available until the Supabase migration is applied.";
  }
  if (error.code === "42501") {
    return "The database rejected this request. Check the current RLS policies.";
  }
  return error.message;
}

export function caughtError(error: unknown) {
  return error instanceof Error
    ? `Request failed: ${error.message}`
    : "Request failed. Check your connection and try again.";
}

export function validateClassInput(name: string, section: string) {
  if (!name.trim() || !section.trim()) {
    return "Class name and section are required.";
  }
  return null;
}

export function validatePersonInput(
  role: PersonRole,
  name: string,
  identifier: string,
  classId: string,
  classIds: string[],
) {
  if (!name.trim() || !identifier.trim()) {
    return role === "student"
      ? "Student name and roll number are required."
      : "Teacher name and employee ID are required.";
  }
  if (role === "student" && !classId) {
    return "Choose a class for the student.";
  }
  if (role === "teacher" && !classIds.length) {
    return "Assign at least one class to the teacher.";
  }
  return null;
}
