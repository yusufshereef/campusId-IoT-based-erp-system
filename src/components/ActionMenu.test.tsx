import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ActionMenu } from "./ActionMenu";
import { actionMenuItemClass, actionMenuPosition } from "../lib/action_menu";

describe("row action menu", () => {
    it("renders an accessible button trigger", () => {
        const html = renderToStaticMarkup(
            <ActionMenu label="Actions for CSE A">
                <button role="menuitem">Delete class</button>
            </ActionMenu>,
        );
        expect(html).toContain('aria-haspopup="menu"');
        expect(html).toContain('aria-expanded="false"');
        expect(html).toContain('aria-label="Actions for CSE A"');
    });

    it("anchors to the right edge and flips above when the table is near the viewport bottom", () => {
        expect(
            actionMenuPosition(
                { top: 700, right: 990, bottom: 732 },
                176,
                80,
                1000,
                800,
            ),
        ).toEqual({ left: 814, top: 616 });
        expect(
            actionMenuPosition(
                { top: 200, right: 990, bottom: 232 },
                176,
                80,
                1000,
                800,
            ),
        ).toEqual({ left: 814, top: 236 });
    });

    it("marks destructive actions for muted red styling", () => {
        expect(actionMenuItemClass(true)).toBe("menu-danger");
    });
});
