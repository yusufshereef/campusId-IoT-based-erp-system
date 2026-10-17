import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ToastViewport, toastDuration } from "./ToastViewport";
import { creationToastMessage } from "../lib/toast_messages";

describe("toast notifications", () => {
    it("renders success content and a labeled close control", () => {
        const html = renderToStaticMarkup(
            <ToastViewport
                toasts={[{ id: 1, kind: "success", message: "Class created" }]}
                onDismiss={() => {}}
            />,
        );
        expect(html).toContain("Class created");
        expect(html).toContain('role="status"');
        expect(html).toContain('aria-label="Dismiss notification"');
        expect(html).toContain('class="toast-timer-fill" style="animation-duration:3500ms"');
    });

  it("stacks multiple notifications and uses longer error timing", () => {
        const html = renderToStaticMarkup(
            <ToastViewport
                toasts={[
                    { id: 1, kind: "success", message: "Student created" },
                    { id: 2, kind: "error", message: "Failed to delete class" },
                ]}
                onDismiss={() => {}}
            />,
        );
        expect(html.match(/class="toast toast-/g) || []).toHaveLength(2);
        expect(toastDuration("success")).toBe(3500);
        expect(toastDuration("warning")).toBe(4500);
    expect(toastDuration("error")).toBe(6500);
  });

  it("keeps the visible stack limited to the newest four notifications", () => {
    const html = renderToStaticMarkup(
      <ToastViewport
        toasts={Array.from({ length: 5 }, (_, id) => ({
          id,
          kind: "info" as const,
          message: `Notice ${id + 1}`,
        }))}
        onDismiss={() => {}}
      />,
    );
    expect(html).not.toContain("Notice 1");
    expect(html).toContain("Notice 5");
    expect((html.match(/class="toast toast-info/g) || [])).toHaveLength(4);
  });

    it("provides the requested creation feedback for each record type", () => {
        expect(creationToastMessage("class")).toBe("Class created");
        expect(creationToastMessage("student")).toBe("Student created");
        expect(creationToastMessage("teacher")).toBe("Teacher created");
    });
});
