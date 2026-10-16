import type { Device, EnrollmentStatus } from "./types";

export function indexEnrollmentStatuses(rows: EnrollmentStatus[]) {
    const statuses: Record<string, EnrollmentStatus> = {};
    for (const row of rows) statuses[row.person_id] = row;
    return statuses;
}

export function canRequestEnrollment(
    status: EnrollmentStatus | undefined,
    terminalOnline: boolean,
    mutationPending: boolean,
) {
    return (
        terminalOnline &&
        !mutationPending &&
        status?.enrollment_status !== "in_progress" &&
        status?.enrollment_status !== "enrolled"
    );
}

export function enrollmentStarted(
    current: Record<string, EnrollmentStatus>,
    personId: string,
    device: Device,
    commandId: string,
) {
    if (current[personId]?.command_id === commandId) return current;
    return {
        ...current,
        [personId]: {
            person_id: personId,
            device_code: device.device_code,
            display_name: device.display_name,
            slot_id: null,
            enrollment_status: "in_progress" as const,
            command_id: commandId,
            command_status: "pending",
            error_message: null,
        },
    };
}
