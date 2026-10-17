import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { DestructiveConfirmationModal } from "./DestructiveConfirmationModal";

function renderModal(overrides: Partial<Parameters<typeof DestructiveConfirmationModal>[0]> = {}) {
  return renderToStaticMarkup(
    <DestructiveConfirmationModal
      title="Delete class?"
      description="This action cannot be undone."
      expectedValue="CSE-A"
      expectedPrompt="Type the class code to confirm:"
      confirmLabel="Delete class"
      tone="danger"
      loading={false}
      error={null}
      onConfirm={vi.fn()}
      onCancel={vi.fn()}
      {...overrides}
    />,
  );
}

describe("destructive confirmation modal", () => {
  it("keeps typed destructive actions disabled until the exact token is entered", () => {
    const markup = renderModal();
    expect(markup).toContain("Type the class code to confirm:");
    expect(markup).toContain('<code class="confirmation-token">CSE-A</code>');
    expect(markup).toContain('value=""');
    expect(markup).toContain("disabled=\"\">Delete class");
  });

  it("requires an explicit click for untyped fingerprint confirmation", () => {
    const markup = renderModal({
      title: "Delete fingerprint?",
      expectedValue: undefined,
      expectedPrompt: undefined,
      confirmLabel: "Delete fingerprint",
    });
    expect(markup).not.toContain('aria-label="Confirmation text"');
    expect(markup).toContain("Delete fingerprint</button>");
    expect(markup).not.toContain("disabled=\"\">Delete fingerprint");
  });

  it("disables cancel and confirmation while submitting and shows inline errors", () => {
    const markup = renderModal({ loading: true, error: "Class has assigned students." });
    expect(markup).toContain('role="alert"');
    expect(markup).toContain("Class has assigned students.");
    expect(markup.match(/disabled=""/g)?.length).toBe(2);
    expect(markup).toContain("Working…");
  });
});
