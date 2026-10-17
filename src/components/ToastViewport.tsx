import { useEffect, useRef, useState } from "react";
import { Check, Info, TriangleAlert, X, XCircle } from "lucide-react";
import type { Notice } from "../lib/types";

export type ToastItem = Notice & { id: number };

export function toastDuration(kind: Notice["kind"]): number {
    if (kind === "error") return 6500;
    if (kind === "warning") return 4500;
    return 3500;
}

type ToastViewportProps = {
    toasts: ToastItem[];
    onDismiss: (id: number) => void;
};

function Toast({
    toast,
    onDismiss,
}: {
    toast: ToastItem;
    onDismiss: (id: number) => void;
}) {
    const [exiting, setExiting] = useState(false);
    const dismissRef = useRef(onDismiss);
    dismissRef.current = onDismiss;
    useEffect(() => {
        const exitTimer = window.setTimeout(
            () => setExiting(true),
            toastDuration(toast.kind),
        );
        const removeTimer = window.setTimeout(
            () => dismissRef.current(toast.id),
            toastDuration(toast.kind) + 180,
        );
        return () => {
            window.clearTimeout(exitTimer);
            window.clearTimeout(removeTimer);
        };
    }, [toast.id, toast.kind]);

    function dismiss() {
        if (exiting) return;
        setExiting(true);
        window.setTimeout(() => dismissRef.current(toast.id), 180);
    }

    const Icon =
        toast.kind === "success"
            ? Check
            : toast.kind === "error"
              ? XCircle
              : toast.kind === "warning"
                ? TriangleAlert
                : Info;
    return (
        <div
            className={`toast toast-${toast.kind}${exiting ? " is-exiting" : ""}`}
            role={toast.kind === "error" ? "alert" : "status"}
        >
            <Icon className="toast-icon" size={17} aria-hidden="true" />
            <p>{toast.message}</p>
            <button
                className="toast-close"
                aria-label="Dismiss notification"
                onClick={dismiss}
            >
                <X size={15} aria-hidden="true" />
            </button>
        </div>
    );
}

export function ToastViewport({ toasts, onDismiss }: ToastViewportProps) {
    const visible = toasts.slice(-4);
    return (
        <div className="toast-viewport" aria-label="Notifications">
            {visible.map((toast) => (
                <Toast key={toast.id} toast={toast} onDismiss={onDismiss} />
            ))}
        </div>
    );
}
