import {
    useEffect,
    useId,
    useLayoutEffect,
    useRef,
    useState,
    type MouseEvent,
    type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { MoreHorizontal } from "lucide-react";
import { actionMenuPosition } from "../lib/action_menu";

const menuEvent = "campusid:action-menu-open";

type ActionMenuProps = { label: string; children: ReactNode };

export function ActionMenu({ label, children }: ActionMenuProps) {
    const id = useId();
    const [open, setOpen] = useState(false);
    const [position, setPosition] = useState({ top: -1000, left: -1000 });
    const trigger = useRef<HTMLButtonElement>(null);
    const menu = useRef<HTMLDivElement>(null);

    function close(restoreFocus = false) {
        setOpen(false);
        if (restoreFocus) trigger.current?.focus();
    }

    function updatePosition() {
        const rect = trigger.current?.getBoundingClientRect();
        if (!rect) return;
        const menuWidth = menu.current?.offsetWidth || 176;
        const menuHeight = menu.current?.offsetHeight || 40;
        setPosition(
            actionMenuPosition(
                rect,
                menuWidth,
                menuHeight,
                window.innerWidth,
                window.innerHeight,
            ),
        );
    }

    function toggle() {
        if (open) {
            close();
            return;
        }
        window.dispatchEvent(new CustomEvent(menuEvent, { detail: id }));
        setOpen(true);
    }

    useLayoutEffect(() => {
        if (!open) return;
        updatePosition();
        const onOutside = (event: PointerEvent) => {
            if (
                !trigger.current?.contains(event.target as Node) &&
                !menu.current?.contains(event.target as Node)
            )
                close();
        };
        const onKeyDown = (event: KeyboardEvent) => {
            if (event.key === "Escape") {
                event.preventDefault();
                close(true);
            } else if (event.key === "ArrowDown" && menu.current) {
                event.preventDefault();
                menu.current
                    .querySelector<HTMLElement>("[role=menuitem]")
                    ?.focus();
            }
        };
        document.addEventListener("pointerdown", onOutside);
        document.addEventListener("keydown", onKeyDown);
        window.addEventListener("resize", updatePosition);
        window.addEventListener("scroll", updatePosition, true);
        return () => {
            document.removeEventListener("pointerdown", onOutside);
            document.removeEventListener("keydown", onKeyDown);
            window.removeEventListener("resize", updatePosition);
            window.removeEventListener("scroll", updatePosition, true);
        };
    }, [open]);

    useEffect(() => {
        const onOtherMenu = (event: Event) => {
            if ((event as CustomEvent<string>).detail !== id) setOpen(false);
        };
        window.addEventListener(menuEvent, onOtherMenu);
        return () => window.removeEventListener(menuEvent, onOtherMenu);
    }, [id]);

    function closeAfterSelection(event: MouseEvent<HTMLDivElement>) {
        if ((event.target as HTMLElement).closest("button")) close(true);
    }

    return (
        <>
            <button
                ref={trigger}
                type="button"
                className="action-menu-trigger"
                aria-label={label}
                aria-haspopup="menu"
                aria-expanded={open}
                aria-controls={`${id}-menu`}
                title={label}
                onClick={toggle}
            >
                <MoreHorizontal size={17} aria-hidden="true" />
            </button>
            {open &&
                createPortal(
                    <div
                        ref={menu}
                        id={`${id}-menu`}
                        className="action-menu-list"
                        role="menu"
                        aria-label={label}
                        style={{
                            position: "fixed",
                            top: position.top,
                            left: position.left,
                        }}
                        onClick={closeAfterSelection}
                    >
                        {children}
                    </div>,
                    document.body,
                )}
        </>
    );
}
