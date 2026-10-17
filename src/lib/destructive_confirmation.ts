export function confirmationMatches(input: string, expected: string) {
  return input.trim() === expected;
}

export function teacherConfirmationValue(employeeId: string | null) {
  return employeeId?.trim() ? employeeId : "DELETE";
}

export function classConfirmationValue(name: string, section: string) {
  return `${name}-${section}`;
}
