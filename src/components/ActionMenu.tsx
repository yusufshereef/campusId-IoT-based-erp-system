import { MoreHorizontal } from "lucide-react";
import type { MouseEvent, ReactNode } from "react";

type ActionMenuProps = {
  label: string;
  children: ReactNode;
};

export function ActionMenu({ label, children }: ActionMenuProps) {
  function closeAfterSelection(event: MouseEvent<HTMLDetailsElement>) {
    if ((event.target as HTMLElement).closest("button"))
      event.currentTarget.open = false;
  }

  return (
    <details className="action-menu" onClick={closeAfterSelection}>
      <summary aria-label={label} title={label}>
        <MoreHorizontal size={17} aria-hidden="true" />
      </summary>
      <div className="action-menu-list" role="menu" aria-label={label}>
        {children}
      </div>
    </details>
  );
}
