import {
  ArrowRight,
  BookOpen,
  Check,
  Cpu,
  Fingerprint,
  GraduationCap,
  Radio,
  ShieldCheck,
  Users,
} from "lucide-react";
import type { CampusClass, Device, Person, Tab } from "../lib/types";
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
  onNavigate: (tab: Tab) => void;
};

export function Overview({
  classes,
  students,
  teachers,
  connected,
  loading,
  isAdmin,
  device,
  deviceError,
  onNavigate,
}: OverviewProps) {
  const terminalOnline = deviceStatus(device);
  const enrolled = students.filter(
    (student) => student.fingerprint_status === "enrolled",
  ).length;
  const metrics = [
    {
      icon: BookOpen,
      label: isAdmin ? "Classes" : "Assigned classes",
      value: classes.length,
      detail: "Academic groups",
    },
    {
      icon: GraduationCap,
      label: "Students",
      value: students.length,
      detail: `${students.filter((student) => student.active).length} active students`,
    },
    {
      icon: Users,
      label: "Teachers",
      value: teachers.length,
      detail: "Visible to your account",
    },
    {
      icon: Fingerprint,
      label: "Student fingerprints",
      value: enrolled,
      detail: "Enrollment records",
    },
  ];
  const steps = [
    {
      title: "Create your classes",
      detail: "Organize sections and academic years.",
      complete: classes.length > 0,
      tab: "classes" as const,
    },
    {
      title: "Build your roster",
      detail: "Register students and assign teachers.",
      complete: students.length > 0 && teachers.length > 0,
      tab: "students" as const,
    },
    {
      title: "Take attendance",
      detail: "Open a class, choose a date, and mark the roster.",
      complete: false,
      tab: "attendance" as const,
    },
  ];

  return (
    <>
      <section className="overview-hero">
        <div>
          <span className="eyebrow">
            <Radio size={14} /> CONNECTED CAMPUS · PROTOTYPE
          </span>
          <h2>
            Every presence.
            <br />
            <span>A clearer picture.</span>
          </h2>
          <p>
            Your people, classes, and attendance in one workspace. Built for the
            next step: a connected fingerprint terminal.
          </p>
          <button className="primary" onClick={() => onNavigate("attendance")}>
            Open attendance <ArrowRight size={17} />
          </button>
        </div>
        <div className="terminal-illustration" aria-hidden="true">
          <div className="terminal-top">
            <span className="dot" /> CAMPUSID <span>01</span>
          </div>
          <Fingerprint className="terminal-finger" strokeWidth={1} />
          <div className="terminal-line" />
          <strong>IDENTITY. CONNECTED.</strong>
          <small>ESP32 + R307S</small>
        </div>
      </section>
      <section
        className="stats"
        aria-label="Workspace counts"
        aria-busy={loading}
      >
        {metrics.map(({ icon: Icon, label, value, detail }) => (
          <div className="stat" key={label}>
            <Icon aria-hidden="true" />
            <small>{label}</small>
            <strong>{loading ? "—" : value}</strong>
            <p>{detail}</p>
          </div>
        ))}
      </section>
      <section className="panel device-status-card">
        <div className="section-heading">
          <div>
            <span className="eyebrow">DEVICE HEALTH</span>
            <h2>{device?.display_name || "CampusID Terminal 01"}</h2>
          </div>
          <Radio size={20} />
        </div>
        {deviceError ? (
          <p className="system-note">{deviceError}</p>
        ) : (
          <>
            <div className="device-status-heading">
              <span
                className={`status-dot ${terminalOnline ? "" : "offline"}`}
              />
              <strong>{terminalOnline ? "ONLINE" : "OFFLINE"}</strong>
            </div>
            <div className="device-health-grid">
              <div>
                <small>Fingerprint sensor</small>
                <b>{device?.sensor_ready ? "Ready" : "Not ready"}</b>
              </div>
              <div>
                <small>Last seen</small>
                <b>{formatLastSeen(device?.last_seen_at || null)}</b>
              </div>
              <div>
                <small>Pending sync</small>
                <b>{device?.pending_event_count ?? 0}</b>
              </div>
              <div>
                <small>Firmware</small>
                <b>{device?.firmware_version || "—"}</b>
              </div>
            </div>
          </>
        )}
      </section>
      <div className="overview-grid">
        <section className="panel">
          <div className="section-heading">
            <div>
              <span className="eyebrow">YOUR WORKFLOW</span>
              <h2>
                {isAdmin
                  ? "From roster to attendance"
                  : "Ready for your next class"}
              </h2>
            </div>
            <BookOpen size={20} />
          </div>
          <div className="workflow-steps">
            {(isAdmin ? steps : steps.slice(2)).map((step, index) => (
              <button
                className="workflow-step"
                onClick={() => onNavigate(step.tab)}
                key={step.title}
              >
                <span
                  className={`step-number ${step.complete ? "complete" : ""}`}
                >
                  {step.complete ? (
                    <Check size={17} />
                  ) : (
                    String(index + 1).padStart(2, "0")
                  )}
                </span>
                <span>
                  <b>{step.title}</b>
                  <small>{step.detail}</small>
                </span>
                <ArrowRight size={17} />
              </button>
            ))}
          </div>
        </section>
        <section className="panel system-panel">
          <div className="section-heading">
            <div>
              <span className="eyebrow">SYSTEM READINESS</span>
              <h2>Connected, with clarity</h2>
            </div>
            <Cpu size={20} />
          </div>
          <div className="system-row">
            <span>
              <ShieldCheck size={18} /> Database
            </span>
            <span className={`badge ${connected ? "success" : "warning"}`}>
              {loading ? "Checking" : connected ? "Connected" : "Unavailable"}
            </span>
          </div>
          <div className="system-row">
            <span>
              <Fingerprint size={18} /> Fingerprint terminal
            </span>
            <span className="badge neutral">Not integrated</span>
          </div>
          <div className="system-row">
            <span>
              <Radio size={18} /> Offline sync
            </span>
            <span className="badge neutral">Planned</span>
          </div>
          <p className="system-note">
            Manual attendance is available now. Terminal recognition runs
            locally; cloud enrollment and sync are the next milestone.
          </p>
        </section>
      </div>
    </>
  );
}
