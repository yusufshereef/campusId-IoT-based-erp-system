import { describe, expect, it } from "vitest";
import { databaseError } from "./admin";
import type { CampusClass, Person } from "./types";
import { withoutClass, withoutPerson } from "./record_deletion";

describe("record deletion list updates", () => {
    it("removes only the deleted row from local lists", () => {
        const people = [{ id: "student-1" }, { id: "teacher-1" }] as Person[];
        const classes = [{ id: "class-1" }, { id: "class-2" }] as CampusClass[];
        expect(
            withoutPerson(people, "student-1").map((person) => person.id),
        ).toEqual(["teacher-1"]);
        expect(withoutClass(classes, "class-1").map((item) => item.id)).toEqual(
            ["class-2"],
        );
    });

    it("shows guarded RPC errors as readable messages", () => {
        expect(
            databaseError({
                code: "P0001",
                message:
                    "Remove the student's fingerprint before deleting this student.",
            }),
        ).toBe(
            "Remove the student's fingerprint before deleting this student.",
        );
    });
});
