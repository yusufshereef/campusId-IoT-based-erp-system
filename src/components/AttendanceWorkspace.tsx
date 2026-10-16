import { useEffect, useMemo, useRef, useState } from "react";
import { CalendarDays, Play, RefreshCw, Search, Square } from "lucide-react";
import { supabase } from "../lib/supabase";
import { caughtError } from "../lib/admin";
import {
  AttendanceRequestError,
  createAttendanceEventId,
  loadAttendance,
  saveAttendance,
  summarizeAttendance,
  type AttendanceRecord,
  type AttendanceStatus,
} from "../lib/attendance";
import type { CampusClass, Notify, Person } from "../lib/types";

function localDate() {
  const date = new Date();
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000)
    .toISOString()
    .slice(0, 10);
}

const statuses = ["present", "late", "excused", "absent"] as const;
const statusLabel = (status: string) =>
  status[0].toUpperCase() + status.slice(1);

type AttendanceProps = {
  classes: CampusClass[];
  students: Person[];
  userId: string;
  notify: Notify;
};

export function AttendanceWorkspace({
  classes,
  students,
  userId,
  notify,
}: AttendanceProps) {
  const [classId, setClassId] = useState("");
  const [date, setDate] = useState(localDate);
  const [records, setRecords] = useState<AttendanceRecord[]>([]);
  const [active, setActive] = useState(false);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState("");
  const [unmarkedOnly, setUnmarkedOnly] = useState(false);
  const [lastLoaded, setLastLoaded] = useState<Date | null>(null);
  // A synchronous lock closes the gap before React disables the controls.
  const requestPending = useRef(false);
  const requestGeneration = useRef(0);
  const pendingEvents = useRef(new Map<string, string>());

  useEffect(
    () => () => {
      requestGeneration.current += 1;
    },
    [],
  );

  const selectedClass = classes.find((item) => item.id === classId);
  const roster = useMemo(
    () =>
      students
        .filter((student) => student.class_id === classId)
        .sort((a, b) => a.full_name.localeCompare(b.full_name)),
    [students, classId],
  );
  const byStudent = useMemo(
    () => new Map(records.map((record) => [record.student_id, record])),
    [records],
  );
  // Inactive people remain visible for history, but are not pending attendance.
  const eligibleIds = roster
    .filter((student) => student.active || byStudent.has(student.id))
    .map((student) => student.id);
  const summary = summarizeAttendance(eligibleIds, records);
  const marked = eligibleIds.length - summary.unmarked;
  const visible = roster.filter(
    (student) =>
      (!unmarkedOnly || (student.active && !byStudent.has(student.id))) &&
      `${student.full_name} ${student.roll_number || ""}`
        .toLowerCase()
        .includes(search.trim().toLowerCase()),
  );

  async function refreshSession() {
    if (!supabase || !classId || !date || requestPending.current) return;
    requestPending.current = true;
    const generation = ++requestGeneration.current;
    setLoading(true);
    try {
      const next = await loadAttendance(supabase, classId, date);
      if (generation !== requestGeneration.current) return;
      setRecords(next);
      setActive(true);
      setLastLoaded(new Date());
    } catch (error) {
      if (generation === requestGeneration.current)
        notify(caughtError(error), "error");
    } finally {
      if (generation === requestGeneration.current) {
        requestPending.current = false;
        setLoading(false);
      }
    }
  }

  function endSession() {
    requestGeneration.current += 1;
    setActive(false);
    setRecords([]);
    setSearch("");
    setUnmarkedOnly(false);
    setLastLoaded(null);
    // Preserve unresolved event IDs so reopening and retrying stays idempotent.
    notify(
      "Session closed. Saved attendance remains available when you reopen it.",
    );
  }

  async function mark(student: Person, status: AttendanceStatus) {
    if (
      !supabase ||
      !active ||
      !selectedClass ||
      !student.active ||
      requestPending.current
    )
      return;
    const existing = byStudent.get(student.id);
    if (existing?.status === status) return;
    requestPending.current = true;
    const generation = ++requestGeneration.current;
    const current = () => generation === requestGeneration.current;
    const eventKey = `${classId}:${student.id}:${date}`;
    const eventId = existing
      ? undefined
      : (pendingEvents.current.get(eventKey) ?? createAttendanceEventId());
    if (eventId) pendingEvents.current.set(eventKey, eventId);
    setLoading(true);
    try {
      const saved = await saveAttendance(supabase, {
        id: existing?.id,
        classId,
        studentId: student.id,
        attendanceDate: date,
        status,
        userId,
        clientEventId: eventId,
      });
      if (!current()) return;
      setRecords((previous) => [
        ...previous.filter((record) => record.student_id !== student.id),
        saved,
      ]);
      pendingEvents.current.delete(eventKey);
      notify(`${student.full_name} marked ${status}.`);
    } catch (error) {
      if (!current()) return;
      // A timeout does not mean the transaction failed. Read before retrying.
      try {
        const latest = await loadAttendance(supabase, classId, date);
        if (!current()) return;
        setRecords(latest);
        setLastLoaded(new Date());
        const confirmed = latest.find(
          (record) => record.student_id === student.id,
        );
        if (
          error instanceof AttendanceRequestError &&
          error.outcome === "unknown" &&
          eventId &&
          confirmed?.client_event_id === eventId
        ) {
          pendingEvents.current.delete(eventKey);
          notify(`Attendance was saved. Current status: ${confirmed.status}.`);
        } else if (
          error instanceof AttendanceRequestError &&
          error.code === "23505"
        ) {
          pendingEvents.current.delete(eventKey);
          notify(
            "This student already has attendance. The latest server status is shown.",
            "error",
          );
        } else {
          if (
            !(error instanceof AttendanceRequestError) ||
            error.outcome !== "unknown"
          )
            pendingEvents.current.delete(eventKey);
          notify(
            error instanceof AttendanceRequestError &&
              error.outcome === "unknown"
              ? "The save could not be confirmed. Review the latest status before retrying."
              : caughtError(error),
            "error",
          );
        }
      } catch {
        if (current())
          notify(
            "The save could not be confirmed and the latest records are unavailable. Reconnect and refresh before retrying.",
            "error",
          );
      }
    } finally {
      if (current()) {
        requestPending.current = false;
        setLoading(false);
      }
    }
  }

  return (
    <>
      <section className="panel attendance-panel" aria-busy={loading}>
        <div className="listhead">
          <div>
            <span className="eyebrow">MANUAL ATTENDANCE</span>
            <h2>
              {active ? "Your class is in session" : "Ready when your class is"}
            </h2>
            <p className="muted">
              {active
                ? "Mark the roster below. Every confirmed change is saved automatically."
                : "Choose a class and date to open its attendance roster."}
            </p>
          </div>
          {active && (
            <button
              className="outline end-session"
              onClick={endSession}
              disabled={loading}
            >
              <Square size={14} /> End session
            </button>
          )}
        </div>
        <div className="attendance-controls">
          <label>
            Class
            <select
              value={classId}
              disabled={active || loading}
              onChange={(event) => setClassId(event.target.value)}
            >
              <option value="">Select a class</option>
              {classes.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name} · {item.section} {item.academic_year || ""}
                </option>
              ))}
            </select>
          </label>
          <label>
            Attendance date
            <input
              type="date"
              value={date}
              disabled={active || loading}
              onChange={(event) => setDate(event.target.value)}
            />
          </label>
          <button
            className={active ? "outline" : "primary"}
            onClick={() => void refreshSession()}
            disabled={loading || !classId || !date}
          >
            {active ? (
              <RefreshCw size={16} className={loading ? "spin" : ""} />
            ) : (
              <Play size={16} />
            )}
            {loading
              ? "Loading…"
              : active
                ? "Refresh roster"
                : "Start attendance"}
          </button>
        </div>
        <p className="field-hint">
          Dates use your browser’s local calendar. One attendance record per
          student, class, and day.
        </p>
        {!classes.length && (
          <div className="empty">
            <CalendarDays />
            <b>No classes assigned yet</b>
            <span>
              An administrator needs to create and assign your class first.
            </span>
          </div>
        )}
      </section>
      {active && selectedClass && (
        <>
          <section
            className="panel progress-panel"
            aria-label="Roster completion"
          >
            <div>
              <b>
                {marked} of {eligibleIds.length} marked
              </b>
              <span>
                {summary.unmarked === 0 && eligibleIds.length
                  ? "Roster complete"
                  : "Work through the unmarked students"}
              </span>
            </div>
            <progress
              value={marked}
              max={eligibleIds.length || 1}
              aria-label="Attendance marked"
            />
          </section>
          <section
            className="stats attendance-stats"
            aria-label="Attendance summary"
          >
            {[...statuses, "unmarked" as const].map((status) => (
              <div className={`stat attendance-stat ${status}`} key={status}>
                <small>
                  {status === "unmarked"
                    ? "Not yet marked"
                    : statusLabel(status)}
                </small>
                <strong>{summary[status]}</strong>
              </div>
            ))}
          </section>
          <section className="panel">
            <div className="listhead">
              <div>
                <h2>
                  {selectedClass.name} · {selectedClass.section}
                </h2>
                <p className="muted">
                  {date} · {roster.length} students ·{" "}
                  {lastLoaded
                    ? `Roster loaded ${lastLoaded.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`
                    : ""}
                </p>
              </div>
              <label className="search">
                <Search size={17} />
                <input
                  aria-label="Search attendance students"
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search name or roll number"
                />
              </label>
            </div>
            <div className="roster-toolbar">
              <label className="check">
                <input
                  type="checkbox"
                  checked={unmarkedOnly}
                  onChange={(event) => setUnmarkedOnly(event.target.checked)}
                />{" "}
                Show only unmarked
              </label>
              <span>{visible.length} shown</span>
            </div>
            <div
              className="tablewrap attendance-roster"
              tabIndex={0}
              role="region"
              aria-label="Attendance roster, scroll horizontally on small screens"
            >
              <table>
                <thead>
                  <tr>
                    <th scope="col">Student</th>
                    <th scope="col">Status</th>
                    <th scope="col">Mark or correct</th>
                  </tr>
                </thead>
                <tbody>
                  {visible.map((student) => {
                    const record = byStudent.get(student.id);
                    return (
                      <tr key={student.id}>
                        <td>
                          <b>{student.full_name}</b>
                          <small className="block">
                            {student.roll_number || "No roll number"}
                            {!student.active && " · Inactive"}
                          </small>
                        </td>
                        <td>
                          <span
                            className={`attendance-status ${record?.status || "unmarked"}`}
                          >
                            {record
                              ? statusLabel(record.status)
                              : student.active
                                ? "Not yet marked"
                                : "Inactive"}
                          </span>
                        </td>
                        <td>
                          <div className="attendance-actions">
                            {statuses.map((status) => (
                              <button
                                className={`outline ${record?.status === status ? "selected" : ""}`}
                                key={status}
                                aria-label={`Mark ${student.full_name} ${status}`}
                                aria-pressed={record?.status === status}
                                disabled={
                                  loading ||
                                  !student.active ||
                                  record?.status === status
                                }
                                onClick={() => void mark(student, status)}
                              >
                                {statusLabel(status)}
                              </button>
                            ))}
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {!visible.length && (
              <div className="empty">
                <Search />
                <b>
                  {roster.length
                    ? "No students match this view"
                    : "This class has no students yet"}
                </b>
                <span>
                  {roster.length
                    ? "Clear your search or turn off the unmarked filter."
                    : "Register students and assign them to this class to get started."}
                </span>
              </div>
            )}
          </section>
        </>
      )}
    </>
  );
}
