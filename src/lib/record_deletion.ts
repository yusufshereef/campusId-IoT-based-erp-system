import type { CampusClass, Person } from "./types";

export function withoutPerson(people: Person[], personId: string) {
    return people.filter((person) => person.id !== personId);
}

export function withoutClass(classes: CampusClass[], classId: string) {
    return classes.filter((item) => item.id !== classId);
}
