import { describe, expect, it } from "vitest";
import {
  caughtError,
  databaseError,
  validateClassInput,
  validatePersonInput,
} from "./admin";

describe("admin validation", () => {
  it("rejects blank class fields after trimming", () => {
    expect(validateClassInput("  ", "A")).toBe(
      "Class name and section are required.",
    );
    expect(validateClassInput("CSE", " ")).toBe(
      "Class name and section are required.",
    );
    expect(validateClassInput("CSE", "A")).toBeNull();
  });

  it("requires identifiers and valid assignments", () => {
    expect(validatePersonInput("student", "Ada", "", "class-1", [])).toContain(
      "roll number",
    );
    expect(validatePersonInput("student", "Ada", "R1", "", [])).toBe(
      "Choose a class for the student.",
    );
    expect(validatePersonInput("teacher", "Ada", "E1", "", [])).toBe(
      "Assign at least one class to the teacher.",
    );
    expect(
      validatePersonInput("teacher", "Ada", "E1", "", ["class-1"]),
    ).toBeNull();
  });
});

describe("database error messages", () => {
  it.each([
    [
      "23505",
      "A record with the same class, roll number, or employee ID already exists.",
    ],
    [
      "23503",
      "The selected class no longer exists. Refresh the page and try again.",
    ],
    ["23514", "The submitted values do not satisfy the database rules."],
    [
      "42883",
      "Teacher registration is not available until the Supabase migration is applied.",
    ],
    [
      "PGRST202",
      "Teacher registration is not available until the Supabase migration is applied.",
    ],
  ])("explains PostgreSQL error %s", (code, message) => {
    expect(databaseError({ code, message: "database detail" })).toBe(message);
  });

  it("reports unknown network failures without hiding them", () => {
    expect(caughtError(new Error("offline"))).toBe("Request failed: offline");
    expect(caughtError("offline")).toBe(
      "Request failed. Check your connection and try again.",
    );
  });
});
