export type MenuRect = { top: number; right: number; bottom: number };
export type MenuPosition = { top: number; left: number };

export function actionMenuItemClass(destructive = false): string {
    return destructive ? "menu-danger" : "";
}

export function actionMenuPosition(
    rect: MenuRect,
    menuWidth: number,
    menuHeight: number,
    viewportWidth: number,
    viewportHeight: number,
): MenuPosition {
    const left = Math.max(
        8,
        Math.min(rect.right - menuWidth, viewportWidth - menuWidth - 8),
    );
    const below = rect.bottom + 4;
    return {
        left,
        top:
            below + menuHeight <= viewportHeight - 8
                ? below
                : Math.max(8, rect.top - menuHeight - 4),
    };
}
