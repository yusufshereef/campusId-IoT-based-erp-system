import { describe, expect, it } from "vitest";
import type { Device, EnrollmentStatus } from "./types";
import {
    canRequestEnrollment,
    enrollmentStarted,
    indexEnrollmentStatuses,
} from "./enrollment_status";

const device = {
    device_code: "terminal-01",
    display_name: "Terminal",
} as Device;

function status(
    enrollment_status: EnrollmentStatus["enrollment_status"],
    command_id: string | null = null,
): EnrollmentStatus {
    return {
        person_id: "student-01",
        device_code: "terminal-01",
        display_name: "Terminal",
        slot_id: enrollment_status === "enrolled" ? 2 : null,
        enrollment_status,
        command_id,
        command_status: command_id ? enrollment_status : null,
        error_message: enrollment_status === "failed" ? "Poor image" : null,
    };
}

describe("remote enrollment status", () => {
    it("blocks a second click while a mutation or command is active", () => {
        expect(canRequestEnrollment(undefined, true, true)).toBe(false);
        expect(
            canRequestEnrollment(
                status("in_progress", "command-01"),
                true,
                false,
            ),
        ).toBe(false);
        expect(
            canRequestEnrollment(status("enrolled", "command-01"), true, false),
        ).toBe(false);
        expect(
            canRequestEnrollment(status("failed", "command-01"), true, false),
        ).toBe(true);
    });

    it("reconstructs an active command from backend status after page refresh", () => {
        const afterRefresh = indexEnrollmentStatuses([
            status("in_progress", "command-01"),
        ]);
        expect(afterRefresh["student-01"].command_id).toBe("command-01");
        expect(
            canRequestEnrollment(afterRefresh["student-01"], true, false),
        ).toBe(false);
    });

    it("keeps the same command on a repeated start", () => {
        const started = enrollmentStarted(
            {},
            "student-01",
            device,
            "command-01",
        );
        expect(
            enrollmentStarted(started, "student-01", device, "command-01"),
        ).toBe(started);
    });

    it("updates in progress to enrolled or failed from status polling", () => {
        const started = enrollmentStarted(
            {},
            "student-01",
            device,
            "command-01",
        );
        expect(started["student-01"].enrollment_status).toBe("in_progress");
        const enrolled = indexEnrollmentStatuses([
            status("enrolled", "command-01"),
        ]);
        expect(enrolled["student-01"].slot_id).toBe(2);
        const failed = indexEnrollmentStatuses([
            status("failed", "command-01"),
        ]);
        expect(failed["student-01"].error_message).toBe("Poor image");
    });
});
