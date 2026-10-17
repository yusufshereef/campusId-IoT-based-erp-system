import { describe, expect, it } from "vitest";
import {
  classConfirmationValue,
  confirmationMatches,
  teacherConfirmationValue,
} from "./destructive_confirmation";

describe("destructive confirmation tokens", () => {
  it("requires an exact student roll number after trimming surrounding input whitespace", () => {
    expect(confirmationMatches(" 26cs001 ", "26cs001")).toBe(true);
    expect(confirmationMatches("26CS001", "26cs001")).toBe(false);
    expect(confirmationMatches("26cs002", "26cs001")).toBe(false);
    expect(confirmationMatches("", "26cs001")).toBe(false);
  });

  it("uses a teacher employee ID or the explicit DELETE fallback", () => {
    expect(teacherConfirmationValue("TCH001")).toBe("TCH001");
    expect(teacherConfirmationValue(null)).toBe("DELETE");
    expect(teacherConfirmationValue("  ")).toBe("DELETE");
  });

  it("derives a class confirmation code from its existing name and section", () => {
    expect(classConfirmationValue("CSE", "A")).toBe("CSE-A");
  });
});
