import { describe, expect, it } from "vitest";
import { validateConfiguration } from "./configuration";

describe("setup validation", () => {
  it("reports missing environment values", () => {
    expect(validateConfiguration("", "")).toContain(".env.local");
  });
  it.each([
    "not-a-url",
    "file:///tmp/example",
    "https://user:password@example.com",
  ])("rejects an unusable project URL: %s", (url) => {
    expect(validateConfiguration(url, "public-key")).toContain("invalid");
  });
  it("accepts a local Supabase development endpoint", () => {
    expect(
      validateConfiguration("http://127.0.0.1:54321", "public-key"),
    ).toBeNull();
  });
  it("rejects a secret API key before creating the browser client", () => {
    expect(
      validateConfiguration("https://example.supabase.co", "sb_secret_test"),
    ).toContain("publishable key");
  });
});
