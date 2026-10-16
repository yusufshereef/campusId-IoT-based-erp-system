import type { CampusClass, Person } from "./types";

export type DeletionKind = "student" | "teacher" | "class";

const confirmationText: Record<DeletionKind, string> = {
    student:
        "Delete student?\nThis permanently removes this student record. This cannot be undone.",
    teacher: "Delete teacher?\nThis permanently removes this teacher record.",
    class: "Delete class?\nThis permanently removes this class.",
};

export function confirmRecordDeletion(
    kind: DeletionKind,
    confirm: (message: string) => boolean,
) {
    return confirm(confirmationText[kind]);
}

export function withoutPerson(people: Person[], personId: string) {
    return people.filter((person) => person.id !== personId);
}

export function withoutClass(classes: CampusClass[], classId: string) {
    return classes.filter((item) => item.id !== classId);
}
