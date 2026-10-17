import {
  AlertTriangle,
  BookOpen,
  CheckCircle2,
  Fingerprint,
  GraduationCap,
  Radio,
  Users,
} from "lucide-react";
import type { CampusClass, Device, EnrollmentStatus, Person } from "../lib/types";
import { deviceStatus, formatLastSeen } from "../lib/device_status";

type OverviewProps = {
  classes: CampusClass[];
  students: Person[];
  teachers: Person[];
  connected: boolean;
  loading: boolean;
  isAdmin: boolean;
  device: Device | null;
  deviceError: string | null;
  now: number;
  enrollmentStatuses: Record<string, EnrollmentStatus>;
  enrollmentStatusAvailable: boolean;
};

const failureStates = new Set([
  "failed",
  "delete_failed",
  "student_delete_failed",
]);

export function Overview({
  classes,
  students,
  teachers,
  connected,
  loading,
  isAdmin,
  device,
  deviceError,
  now,
  enrollmentStatuses,
  enrollmentStatusAvailable,
}: OverviewProps) {
  const terminalOnline = deviceStatus(device, now);
  const statuses = enrollmentStatusAvailable ? Object.values(enrollmentStatuses) : [];
  const enrolled = statuses.filter((status) => status.enrollment_status === "enrolled").length;
  const pendingEnrollment = statuses.filter((status) => status.enrollment_status === "in_progress").length;
  const pendingRemoval = statuses.filter((status) => status.enrollment_status === "delete_processing").length;
  const failedStatuses = statuses.filter((status) => failureStates.has(status.enrollment_status));
  const count = (value: number) => (loading ? "—" : value);
  const biometricCount = (value: number) =>
    loading || !enrollmentStatusAvailable ? "—" : value;

  const attention: string[] = [];
  if (deviceError) attention.push(`Terminal status could not be read: ${deviceError}`);
  else if (!device) attention.push("Fingerprint terminal is not configured.");
  else if (!terminalOnline) attention.push("Fingerprint terminal is offline.");
  if (device && !device.sensor_ready) attention.push("Fingerprint sensor is unavailable.");
  if (failedStatuses.length > 0) {
    attention.push(`${failedStatuses.length} biometric operation${failedStatuses.length === 1 ? "" : "s"} need attention.`);
  }

  return (
    <div className="overview-dashboard">
      <section className="overview-metrics" aria-label="Campus summary" aria-busy={loading}>
        <div className="overview-metric">
          <div><GraduationCap aria-hidden="true" size={16} /><small>Students</small></div>
          <strong>{count(students.length)}</strong>
        </div>
        <div className="overview-metric">
          <div><Users aria-hidden="true" size={16} /><small>Teachers</small></div>
          <strong>{count(teachers.length)}</strong>
        </div>
        <div className="overview-metric">
          <div><BookOpen aria-hidden="true" size={16} /><small>{isAdmin ? "Classes" : "Assigned classes"}</small></div>
          <strong>{count(classes.length)}</strong>
        </div>
        {isAdmin && (
          <div className="overview-metric">
            <div><Fingerprint aria-hidden="true" size={16} /><small>Enrolled fingerprints</small></div>
            <strong>{biometricCount(enrolled)}</strong>
          </div>
        )}
      </section>

      <div className="overview-main-grid">
        <section className="panel overview-panel" aria-labelledby="system-status-title">
          <div className="overview-panel-heading">
            <div>
              <span className="eyebrow">SYSTEM STATUS</span>
              <h2 id="system-status-title">Fingerprint terminal</h2>
            </div>
            <Radio aria-hidden="true" size={17} />
          </div>
          <div className="overview-system-list" aria-busy={loading}>
            <div className="overview-system-row">
              <span>Terminal</span>
              <strong className={terminalOnline ? "state-good" : "state-attention"}>
                {!device ? "Not configured" : terminalOnline ? "Online" : "Offline"}
              </strong>
            </div>
            <div className="overview-system-row">
              <span>Fingerprint sensor</span>
              <strong className={device?.sensor_ready ? "state-good" : "state-attention"}>
                {device ? (device.sensor_ready ? "Ready" : "Unavailable") : "Unknown"}
              </strong>
            </div>
            <div className="overview-system-row">
              <span>Last heartbeat</span>
              <strong>{formatLastSeen(device?.last_seen_at || null, now)}</strong>
            </div>
            {device && (
              <small className="overview-device-code">
                {device.device_code} · {device.firmware_version || "Firmware version unavailable"}
              </small>
            )}
          </div>
        </section>

        {isAdmin && (
          <section className="panel overview-panel" aria-labelledby="biometric-operations-title">
            <div className="overview-panel-heading">
              <div>
                <span className="eyebrow">BIOMETRIC OPERATIONS</span>
                <h2 id="biometric-operations-title">Current status</h2>
              </div>
              <Fingerprint aria-hidden="true" size={17} />
            </div>
            <div className="overview-operation-list" aria-busy={loading || !enrollmentStatusAvailable}>
              <div><span>Pending enrollment</span><strong>{biometricCount(pendingEnrollment)}</strong></div>
              <div><span>Fingerprint removal</span><strong>{biometricCount(pendingRemoval)}</strong></div>
              <div>
                <span>Failed / attention required</span>
                <strong className={failedStatuses.length ? "state-attention" : ""}>
                  {biometricCount(failedStatuses.length)}
                </strong>
              </div>
            </div>
          </section>
        )}
      </div>

      {attention.length > 0 ? (
        <section className="overview-attention" aria-labelledby="overview-attention-title">
          <AlertTriangle aria-hidden="true" size={17} />
          <div>
            <h2 id="overview-attention-title">Needs attention</h2>
            <ul>{attention.map((item) => <li key={item}>{item}</li>)}</ul>
            {failedStatuses.map((status) => {
              const student = students.find((person) => person.id === status.person_id);
              return status.error_message ? (
                <p key={status.command_id || status.person_id}>
                  {student?.full_name ? `${student.full_name}: ` : ""}{status.error_message}
                </p>
              ) : null;
            })}
          </div>
        </section>
      ) : connected && device && terminalOnline && device.sensor_ready && enrollmentStatusAvailable ? (
        <p className="overview-operational" role="status">
          <CheckCircle2 aria-hidden="true" size={16} /> All systems operational
        </p>
      ) : null}
    </div>
  );
}
