export type CreatedEntity = "class" | "student" | "teacher";

export function creationToastMessage(entity: CreatedEntity): string {
    return `${entity[0].toUpperCase()}${entity.slice(1)} created`;
}
