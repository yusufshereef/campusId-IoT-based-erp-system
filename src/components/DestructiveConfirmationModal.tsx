import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { confirmationMatches } from "../lib/destructive_confirmation";

export type DestructiveConfirmationProps = {
  title: string;
  description: string;
  expectedValue?: string;
  expectedPrompt?: string;
  confirmLabel: string;
  tone: "danger" | "warning";
  loading: boolean;
  error: string | null;
  onConfirm: () => void;
  onCancel: () => void;
};

export function DestructiveConfirmationModal({
  title,
  description,
  expectedValue,
  expectedPrompt,
  confirmLabel,
  tone,
  loading,
  error,
  onConfirm,
  onCancel,
}: DestructiveConfirmationProps) {
  const [value, setValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const canConfirm = expectedValue === undefined ||
    (expectedValue.length > 0 && confirmationMatches(value, expectedValue));

  useEffect(() => {
    if (expectedValue === undefined) confirmRef.current?.focus();
    else inputRef.current?.focus();
  }, [expectedValue]);

  function handleKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      if (!loading) onCancel();
      return;
    }
    if (event.key !== "Tab") return;
    const focusable = Array.from(
      event.currentTarget.querySelectorAll<HTMLElement>(
        "input:not(:disabled), button:not(:disabled)",
      ),
    );
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return (
    <div className="modal-backdrop" role="presentation">
      <section
        className="confirmation-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="destructive-confirmation-title"
        aria-describedby="destructive-confirmation-description"
        onKeyDown={handleKeyDown}
      >
        <h2 id="destructive-confirmation-title">{title}</h2>
        <p id="destructive-confirmation-description">{description}</p>
        {expectedValue !== undefined && (
          <>
            <div className="confirmation-token-block">
              <p>{expectedPrompt}</p>
              <code className="confirmation-token">{expectedValue}</code>
            </div>
            <label>
              Confirmation
              <input
                ref={inputRef}
                value={value}
                onChange={(event) => setValue(event.target.value)}
                disabled={loading}
                autoComplete="off"
                aria-label={expectedPrompt || "Confirmation text"}
                aria-invalid={!canConfirm}
              />
            </label>
          </>
        )}
        {error && <p className="confirmation-error" role="alert">{error}</p>}
        <div className="modal-actions">
          <button
            className="outline"
            onClick={() => { if (!loading) onCancel(); }}
            aria-disabled={loading}
          >
            Cancel
          </button>
          <button
            ref={confirmRef}
            className={`outline ${tone === "danger" ? "danger" : "warning"}`}
            onClick={onConfirm}
            disabled={loading || !canConfirm}
          >
            {loading ? "Working…" : confirmLabel}
          </button>
        </div>
      </section>
    </div>
  );
}
