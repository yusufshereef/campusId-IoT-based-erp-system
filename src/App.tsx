import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import type { Session } from "@supabase/supabase-js";
import {
  BookOpen,
  GraduationCap,
  Users,
  LayoutDashboard,
  Fingerprint,
  Plus,
  RefreshCw,
  Search,
  Wifi,
  WifiOff,
  ShieldCheck,
  CalendarDays,
} from "lucide-react";
import { configured, configurationError, supabase } from "./lib/supabase";
import {
  caughtError,
  databaseError,
  validateClassInput,
  validatePersonInput,
} from "./lib/admin";
import { AttendanceWorkspace } from "./components/AttendanceWorkspace";
import { Overview } from "./components/Overview";
import { DEVICE_REFRESH_INTERVAL_MS, deviceStatus } from "./lib/device_status";
import {
  canRequestEnrollment,
  enrollmentStarted,
  indexEnrollmentStatuses,
} from "./lib/enrollment_status";
import {
  confirmRecordDeletion,
  withoutClass,
  withoutPerson,
} from "./lib/record_deletion";
import type {
  CampusClass,
  Device,
  EnrollmentStatus,
  Person,
  Tab,
  Notice,
} from "./lib/types";

export default function App() {
  const [tab, setTab] = useState<Tab>("overview"),
    [classes, setClasses] = useState<CampusClass[]>([]),
    [people, setPeople] = useState<Person[]>([]),
    [assignments, setAssignments] = useState<Record<string, string[]>>({}),
    [enrollmentStatuses, setEnrollmentStatuses] = useState<
      Record<string, EnrollmentStatus>
    >({}),
    [device, setDevice] = useState<Device | null>(null),
    [deviceError, setDeviceError] = useState<string | null>(null),
    [notice, setNotice] = useState<Notice | null>(null),
    [search, setSearch] = useState(""),
    [busy, setBusy] = useState(false),
    [dbConnected, setDbConnected] = useState(false),
    [session, setSession] = useState<Session | null>(null),
    [userRole, setUserRole] = useState<string | null>(null),
    [roleReady, setRoleReady] = useState(false),
    [authReady, setAuthReady] = useState(!supabase),
    [now, setNow] = useState(() => Date.now());
  const sessionRef = useRef<Session | null>(null);
  const sessionGeneration = useRef(0);
  const refreshGeneration = useRef(0);
  const statusRefreshGeneration = useRef(0);
  const statusRefreshPending = useRef(false);
  const mutationPending = useRef(false);
  const [classNameInput, setClassNameInput] = useState(""),
    [section, setSection] = useState("A"),
    [year, setYear] = useState("2026-27"),
    [fullName, setFullName] = useState(""),
    [identifier, setIdentifier] = useState(""),
    [studentClass, setStudentClass] = useState(""),
    [teacherClasses, setTeacherClasses] = useState<string[]>([]),
    [email, setEmail] = useState(""),
    [password, setPassword] = useState("");
  function showNotice(message: string, kind: Notice["kind"] = "success") {
    setNotice({ message, kind });
  }
  const students = useMemo(
      () => people.filter((p) => p.role === "student"),
      [people],
    ),
    teachers = useMemo(
      () => people.filter((p) => p.role === "teacher"),
      [people],
    );
  const terminalOnline = deviceStatus(device, now);
  function isCurrentSession(
    generation: number,
    currentSession: Session | null,
  ) {
    return (
      sessionGeneration.current === generation &&
      sessionRef.current?.user.id === currentSession?.user.id
    );
  }
  async function refresh(silent = false) {
    if (!supabase || !session) {
      setDbConnected(false);
      if (!supabase) {
        showNotice(
          configurationError || "Supabase is not configured.",
          "error",
        );
      }
      return;
    }
    const currentSession = session;
    const generation = sessionGeneration.current;
    const request = ++refreshGeneration.current;
    const statusRequest = ++statusRefreshGeneration.current;
    if (!silent) setBusy(true);
    try {
      const [c, p, a, d, e] = await Promise.all([
        supabase.from("classes").select("*").order("name"),
        supabase
          .from("people")
          .select("*")
          .order("created_at", { ascending: false }),
        supabase.from("teacher_classes").select("teacher_id,class_id"),
        supabase
          .from("devices")
          .select(
            "id,device_code,display_name,last_seen_at,firmware_version,sensor_ready,pending_event_count",
          )
          .order("display_name"),
        supabase.rpc("get_fingerprint_statuses"),
      ]);
      const err = c.error || p.error || a.error;
      if (
        !isCurrentSession(generation, currentSession) ||
        request !== refreshGeneration.current
      )
        return;
      if (err) {
        setDbConnected(false);
        showNotice(databaseError(err), "error");
        return;
      }
      setDbConnected(true);
      const classRows = (c.data || []) as CampusClass[];
      setClasses(classRows);
      setPeople(
        ((p.data || []) as Person[]).map((person) => ({
          ...person,
          classes:
            classRows.find((item) => item.id === person.class_id) || null,
        })),
      );
      const m: Record<string, string[]> = {};
      for (const row of a.data || []) {
        m[row.teacher_id] ??= [];
        m[row.teacher_id].push(row.class_id);
      }
      setAssignments(m);
      setDeviceError(d.error ? databaseError(d.error) : null);
      setDevice((d.data?.[0] as Device | undefined) || null);
      if (statusRequest === statusRefreshGeneration.current && !e.error)
        setEnrollmentStatuses(
          indexEnrollmentStatuses((e.data || []) as EnrollmentStatus[]),
        );
    } catch (error) {
      if (
        !isCurrentSession(generation, currentSession) ||
        request !== refreshGeneration.current
      )
        return;
      setDbConnected(false);
      showNotice(caughtError(error), "error");
    } finally {
      if (
        isCurrentSession(generation, currentSession) &&
        request === refreshGeneration.current && !silent
      )
        setBusy(false);
    }
  }
  async function refreshEnrollmentStatuses() {
    if (!supabase || !session || statusRefreshPending.current) return;
    const currentSession = session;
    const generation = sessionGeneration.current;
    const statusRequest = ++statusRefreshGeneration.current;
    statusRefreshPending.current = true;
    try {
      const { data, error } = await supabase.rpc("get_fingerprint_statuses");
      if (
        error ||
        !isCurrentSession(generation, currentSession) ||
        statusRequest !== statusRefreshGeneration.current
      ) return;
      setEnrollmentStatuses(
        indexEnrollmentStatuses((data || []) as EnrollmentStatus[]),
      );
    } catch {
      // Keep the last known state until the next status poll succeeds.
    } finally {
      statusRefreshPending.current = false;
    }
  }
  useEffect(() => {
    if (!supabase) return;
    let active = true;
    const generation = sessionGeneration.current;
    function receiveSession(nextSession: Session | null) {
      if (!active) return;
      const identityChanged =
        sessionRef.current?.user.id !== nextSession?.user.id;
      sessionRef.current = nextSession;
      setSession(nextSession);
      setAuthReady(true);
      // Token refresh and tab focus must not close an ongoing class session.
      if (!identityChanged) return;
      sessionGeneration.current += 1;
      mutationPending.current = false;
      setBusy(false);
      setUserRole(null);
      setRoleReady(false);
      setClasses([]);
      setPeople([]);
      setAssignments({});
      setDevice(null);
      setDeviceError(null);
      setEnrollmentStatuses({});
      setDbConnected(false);
      setNotice(null);
      setPassword("");
      setTab("overview");
      setSearch("");
      setFullName("");
      setIdentifier("");
      setStudentClass("");
      setTeacherClasses([]);
    }
    void supabase.auth
      .getSession()
      .then(({ data }) => {
        if (active && sessionGeneration.current === generation) {
          receiveSession(data.session);
        }
      })
      .catch((error: unknown) => {
        if (active && sessionGeneration.current === generation) {
          showNotice(caughtError(error), "error");
          setAuthReady(true);
        }
      });
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      receiveSession(nextSession);
    });
    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);
  useEffect(() => {
    if (!session || !supabase) return;
    let active = true;
    const currentSession = session;
    const generation = sessionGeneration.current;
    void (async () => {
      try {
        const { data, error } = await supabase.rpc("current_user_role");
        if (!active || !isCurrentSession(generation, currentSession)) return;
        if (error) {
          setUserRole(null);
          showNotice(databaseError(error), "error");
        } else {
          setUserRole(
            data === "administrator" || data === "teacher" ? data : null,
          );
        }
        setRoleReady(true);
      } catch (error) {
        if (!active || !isCurrentSession(generation, currentSession)) return;
        setUserRole(null);
        setRoleReady(true);
        showNotice(caughtError(error), "error");
      }
    })();
    void refresh();
    return () => {
      active = false;
    };
  }, [session?.user.id]);
  const hasEnrollmentInProgress = Object.values(enrollmentStatuses).some(
    (status) => ["in_progress", "delete_processing"].includes(status.enrollment_status),
  );
  useEffect(() => {
    if (!session || !supabase || !hasEnrollmentInProgress) return;
    const timer = window.setInterval(() => void refreshEnrollmentStatuses(), 2000);
    return () => window.clearInterval(timer);
  }, [session?.user.id, hasEnrollmentInProgress]);
  useEffect(() => {
    if (!session || !supabase) return;
    const timer = window.setInterval(() => {
      void refresh(true);
    }, DEVICE_REFRESH_INTERVAL_MS);
    return () => window.clearInterval(timer);
  }, [session?.user.id]);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);
  async function signIn(e: FormEvent) {
    e.preventDefault();
    if (!supabase) return;
    setBusy(true);
    setNotice(null);
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (error) showNotice(`Sign-in failed: ${error.message}`, "error");
    } catch (error) {
      showNotice(`Sign-in failed: ${caughtError(error)}`, "error");
    } finally {
      setBusy(false);
    }
  }
  async function signOut() {
    if (!supabase) return;
    setBusy(true);
    setNotice(null);
    try {
      const { error } = await supabase.auth.signOut();
      if (error) showNotice(`Sign-out failed: ${error.message}`, "error");
    } catch (error) {
      showNotice(`Sign-out failed: ${caughtError(error)}`, "error");
    } finally {
      setBusy(false);
    }
  }
  async function addClass(e: FormEvent) {
    e.preventDefault();
    if (!supabase || userRole !== "administrator" || mutationPending.current)
      return;
    const className = classNameInput.trim();
    const classSection = section.trim();
    const validationError = validateClassInput(className, classSection);
    if (validationError) {
      showNotice(validationError, "error");
      return;
    }
    const generation = sessionGeneration.current;
    mutationPending.current = true;
    setBusy(true);
    try {
      const { error } = await supabase.from("classes").insert({
        name: className,
        section: classSection,
        academic_year: year.trim() || null,
      });
      if (!isCurrentSession(generation, session)) return;
      if (error) {
        showNotice(databaseError(error), "error");
        return;
      }
      setClassNameInput("");
      showNotice("Class created.");
      await refresh();
    } catch (error) {
      if (isCurrentSession(generation, session))
        showNotice(caughtError(error), "error");
    } finally {
      if (isCurrentSession(generation, session)) {
        mutationPending.current = false;
        setBusy(false);
      }
    }
  }
  async function addPerson(e: FormEvent, role: "student" | "teacher") {
    e.preventDefault();
    if (!supabase || userRole !== "administrator" || mutationPending.current)
      return;
    const personName = fullName.trim();
    const personIdentifier = identifier.trim();
    const validationError = validatePersonInput(
      role,
      personName,
      personIdentifier,
      studentClass,
      teacherClasses,
    );
    if (validationError) {
      showNotice(validationError, "error");
      return;
    }
    const generation = sessionGeneration.current;
    mutationPending.current = true;
    setBusy(true);
    setNotice(null);
    try {
      if (role === "teacher") {
        const { error: teacherError } = await supabase.rpc(
          "register_teacher_with_classes",
          {
            p_full_name: personName,
            p_employee_id: personIdentifier,
            p_class_ids: [...new Set(teacherClasses)],
          },
        );
        if (!isCurrentSession(generation, session)) return;
        if (teacherError) {
          showNotice(databaseError(teacherError), "error");
          return;
        }
      } else {
        const { error } = await supabase.from("people").insert({
          full_name: personName,
          role,
          roll_number: personIdentifier,
          employee_id: null,
          class_id: studentClass,
          fingerprint_status: "not_enrolled",
        });
        if (!isCurrentSession(generation, session)) return;
        if (error) {
          showNotice(databaseError(error), "error");
          return;
        }
      }
      setFullName("");
      setIdentifier("");
      setStudentClass("");
      setTeacherClasses([]);
      showNotice(
        `${role === "student" ? "Student" : "Teacher"} registered. Hardware enrollment is not connected yet.`,
      );
      await refresh();
    } catch (error) {
      if (isCurrentSession(generation, session))
        showNotice(caughtError(error), "error");
    } finally {
      if (isCurrentSession(generation, session)) {
        mutationPending.current = false;
        setBusy(false);
      }
    }
  }
  async function activeToggle(p: Person) {
    if (!supabase || userRole !== "administrator" || mutationPending.current)
      return;
    const generation = sessionGeneration.current;
    mutationPending.current = true;
    setBusy(true);
    try {
      const { error } = await supabase
        .from("people")
        .update({ active: !p.active })
        .eq("id", p.id)
        .select("id")
        .single();
      if (!isCurrentSession(generation, session)) return;
      showNotice(
        error ? databaseError(error) : `${p.full_name} updated.`,
        error ? "error" : "success",
      );
      if (!error) await refresh();
    } catch (error) {
      if (isCurrentSession(generation, session))
        showNotice(caughtError(error), "error");
    } finally {
      if (isCurrentSession(generation, session)) {
        mutationPending.current = false;
        setBusy(false);
      }
    }
  }
  async function deleteStudent(person: Person) {
    if (!supabase || userRole !== "administrator" || mutationPending.current) return;
    if (enrollmentStatuses[person.id]?.slot_id) {
      await requestFingerprintDeletion(person, "student");
      return;
    }
    if (!confirmRecordDeletion("student", (message) => window.confirm(message))) return;
    const generation = sessionGeneration.current;
    refreshGeneration.current++;
    statusRefreshGeneration.current++;
    mutationPending.current = true;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("delete_student", {
        p_person_id: person.id,
      });
      if (!isCurrentSession(generation, session)) return;
      if (error) {
        showNotice(databaseError(error), "error");
        return;
      }
      setPeople((current) => withoutPerson(current, person.id));
      setEnrollmentStatuses((current) => {
        const next = { ...current };
        delete next[person.id];
        return next;
      });
      showNotice(`${person.full_name} deleted.`);
    } catch (error) {
      if (isCurrentSession(generation, session))
        showNotice(caughtError(error), "error");
    } finally {
      if (isCurrentSession(generation, session)) {
        mutationPending.current = false;
        setBusy(false);
      }
    }
  }
  async function deleteTeacher(person: Person) {
    if (!supabase || userRole !== "administrator" || mutationPending.current) return;
    if (!confirmRecordDeletion("teacher", (message) => window.confirm(message))) return;
    const generation = sessionGeneration.current;
    refreshGeneration.current++;
    statusRefreshGeneration.current++;
    mutationPending.current = true;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("delete_teacher", {
        p_person_id: person.id,
      });
      if (!isCurrentSession(generation, session)) return;
      if (error) {
        showNotice(databaseError(error), "error");
        return;
      }
      setPeople((current) => withoutPerson(current, person.id));
      setAssignments((current) => {
        const next = { ...current };
        delete next[person.id];
        return next;
      });
      showNotice(`${person.full_name} deleted.`);
    } catch (error) {
      if (isCurrentSession(generation, session))
        showNotice(caughtError(error), "error");
    } finally {
      if (isCurrentSession(generation, session)) {
        mutationPending.current = false;
        setBusy(false);
      }
    }
  }
  async function deleteClass(classRecord: CampusClass) {
    if (!supabase || userRole !== "administrator" || mutationPending.current) return;
    if (!confirmRecordDeletion("class", (message) => window.confirm(message))) return;
    const generation = sessionGeneration.current;
    refreshGeneration.current++;
    statusRefreshGeneration.current++;
    mutationPending.current = true;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("delete_class", {
        p_class_id: classRecord.id,
      });
      if (!isCurrentSession(generation, session)) return;
      if (error) {
        showNotice(databaseError(error), "error");
        return;
      }
      setClasses((current) => withoutClass(current, classRecord.id));
      setAssignments((current) => {
        const next: Record<string, string[]> = {};
        for (const [teacherId, classIds] of Object.entries(current)) {
          next[teacherId] = classIds.filter((id) => id !== classRecord.id);
        }
        return next;
      });
      showNotice(`${classRecord.name}-${classRecord.section} deleted.`);
    } catch (error) {
      if (isCurrentSession(generation, session))
        showNotice(caughtError(error), "error");
    } finally {
      if (isCurrentSession(generation, session)) {
        mutationPending.current = false;
        setBusy(false);
      }
    }
  }
  async function requestEnrollment(person: Person) {
    if (
      !supabase ||
      userRole !== "administrator" ||
      !device ||
      !terminalOnline ||
      !canRequestEnrollment(
        enrollmentStatuses[person.id],
        terminalOnline,
        mutationPending.current,
      )
    ) {
      if (!terminalOnline) showNotice("Terminal offline.", "error");
      return;
    }
    mutationPending.current = true;
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("create_enrollment_command", {
        p_person_id: person.id,
        p_device_id: device.id,
      });
      if (error) showNotice(databaseError(error), "error");
      else {
        showNotice(`Enrollment started for ${person.full_name}.`);
        setEnrollmentStatuses((current) =>
          enrollmentStarted(current, person.id, device, data as string),
        );
        await refreshEnrollmentStatuses();
      }
    } catch (error) {
      showNotice(caughtError(error), "error");
    } finally {
      mutationPending.current = false;
      setBusy(false);
    }
  }
  async function requestFingerprintDeletion(person: Person, purpose: "remove" | "reenroll" | "student") {
    if (!supabase || userRole !== "administrator" || !terminalOnline || mutationPending.current) {
      if (!terminalOnline) showNotice("Terminal offline.", "error");
      return;
    }
    const prompt = purpose === "remove"
      ? "Remove this fingerprint?\nThe physical fingerprint template will be removed from the CampusID terminal. The student record will remain."
      : purpose === "reenroll"
        ? "Re-enroll fingerprint?\nThe existing physical template will be removed first. Enrollment can start after the terminal confirms deletion."
        : "Delete student?\nThe physical fingerprint template will be removed first. The student record will be deleted only after the terminal confirms removal.";
    if (!window.confirm(prompt)) return;
    mutationPending.current = true;
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("create_fingerprint_delete_command", {
        p_person_id: person.id,
        p_workflow: purpose === "reenroll" ? "reenroll" : purpose === "student" ? "student_delete" : "remove",
      });
      if (error) {
        showNotice(databaseError(error), "error");
        return;
      }
      showNotice(purpose === "remove"
        ? `Fingerprint removal started for ${person.full_name}. The student record will remain.`
        : purpose === "reenroll"
          ? `Fingerprint removal started for ${person.full_name}. Enrollment will start after the terminal confirms deletion.`
          : `Fingerprint removal started for ${person.full_name}. The student will be deleted after the terminal confirms removal, provided attendance history allows deletion.`);
      await refreshEnrollmentStatuses();
    } catch (error) {
      showNotice(caughtError(error), "error");
    } finally {
      mutationPending.current = false;
      setBusy(false);
    }
  }
  function navigate(next: Tab) {
    setTab(next);
    setSearch("");
    setFullName("");
    setIdentifier("");
    setStudentClass("");
    setTeacherClasses([]);
    setNotice(null);
  }
  const descriptions: Record<Tab, string> = {
    overview: "A connected view of your campus, ready for the day ahead.",
    attendance: "Open your class roster and make every presence count.",
    classes: "The academic groups at the heart of your campus.",
    students:
      "Your student directory, class assignments, and enrollment status.",
    teachers: "The people guiding your classes, all in one place.",
  };
  const title =
    tab === "overview"
      ? "Overview"
      : tab === "attendance"
        ? "Attendance"
        : tab === "classes"
          ? "Classes"
          : tab === "students"
            ? "Students"
            : "Teachers";
  function classAssignment(person: Person) {
    const classIds =
      person.role === "teacher"
        ? assignments[person.id] || []
        : person.class_id
          ? [person.class_id]
          : [];
    return classIds
      .map((id) => {
        const assignedClass = classes.find((item) => item.id === id);
        return assignedClass
          ? `${assignedClass.name}-${assignedClass.section}`
          : "";
      })
      .filter(Boolean)
      .join(", ");
  }
  const list = (tab === "students" ? students : teachers).filter((p) =>
    [p.full_name, p.roll_number || "", p.employee_id || "", classAssignment(p)]
      .join(" ")
      .toLowerCase()
      .includes(search.trim().toLowerCase()),
  );
  if (!configured) {
    return (
      <div className="auth-shell">
        <section className="auth-card">
          <div className="logo">
            <Fingerprint />
          </div>
          <p className="eyebrow">CAMPUSID · CONNECTED CAMPUS</p>
          <h1>Connect your Supabase project</h1>
          <p>{configurationError}</p>
        </section>
      </div>
    );
  }
  if (!authReady) {
    return (
      <div className="auth-shell">
        <p>Loading sign-in…</p>
      </div>
    );
  }
  if (!session) {
    return (
      <div className="auth-shell">
        <form className="auth-card" onSubmit={signIn}>
          <div className="logo">
            <Fingerprint />
          </div>
          <p className="eyebrow">CAMPUSID · CONNECTED CAMPUS</p>
          <h1>Welcome to CampusID</h1>
          <p>Use an authorized administrator or teacher account.</p>
          <label>
            Email
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="email"
            />
          </label>
          <label>
            Password
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
            />
          </label>
          {notice && (
            <div
              className={`notice ${notice.kind}`}
              role={notice.kind === "error" ? "alert" : "status"}
            >
              {notice.message}
            </div>
          )}
          <button className="primary" disabled={busy}>
            {busy ? "Signing in…" : "Sign in"}
          </button>
        </form>
      </div>
    );
  }
  if (!roleReady) {
    return (
      <div className="auth-shell">
        <p>Checking account permissions…</p>
      </div>
    );
  }
  if (!userRole) {
    return (
      <div className="auth-shell">
        <section className="auth-card">
          <div className="logo">
            <ShieldCheck />
          </div>
          <p className="eyebrow">CAMPUSID · CONNECTED CAMPUS</p>
          <h1>
            {notice?.kind === "error"
              ? "Unable to verify your account"
              : "Account not provisioned"}
          </h1>
          {notice && (
            <div className={`notice ${notice.kind}`} role="alert">
              {notice.message}
            </div>
          )}
          <p>
            This Auth account does not have an administrator or teacher role.
            Ask the project owner to assign one, then sign in again.
          </p>
          <button
            className="primary"
            onClick={() => void signOut()}
            disabled={busy}
          >
            Sign out
          </button>
        </section>
      </div>
    );
  }
  return (
    <div className="shell">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>
      <aside className="sidebar">
        <div className="brand">
          <div className="logo">
            <Fingerprint />
          </div>
          <div>
            <b>CampusID</b>
            <small>ATTENDANCE SYSTEM</small>
          </div>
        </div>
        <p className="navlabel">WORKSPACE</p>
        <nav aria-label="Main navigation">
          {(
            [
              ["overview", "Overview", LayoutDashboard],
              ["attendance", "Attendance", CalendarDays],
              ["classes", "Classes", BookOpen],
              ["students", "Students", GraduationCap],
              ["teachers", "Teachers", Users],
            ] as const
          ).map(([id, label, Icon]) => (
            <button
              key={id}
              className={"nav " + (tab === id ? "chosen" : "")}
              onClick={() => navigate(id)}
              aria-current={tab === id ? "page" : undefined}
            >
              <Icon size={18} />
              {label}
            </button>
          ))}
        </nav>
        <div className="device">
          <span className={`dot ${terminalOnline ? "" : "offline"}`} />
          <div>
            <b>CampusID Terminal 01</b>
            <small>{terminalOnline ? "Online" : "Offline"}</small>
          </div>
          <em>{terminalOnline ? "LIVE" : "WAITING"}</em>
        </div>
        <div className="admin">
          <span>{userRole === "administrator" ? "AD" : "TC"}</span>
          <div>
            <b>{userRole === "administrator" ? "Administrator" : "Teacher"}</b>
            <small>{session.user.email}</small>
          </div>
          <button
            className="signout"
            onClick={() => void signOut()}
            disabled={busy}
          >
            Sign out
          </button>
        </div>
      </aside>
      <main id="main-content" tabIndex={-1}>
        <header>
          <span>
            Workspace <i>/</i> <b>{title}</b>
          </span>
          <label className={dbConnected ? "good" : "warn"}>
            {dbConnected ? <Wifi size={15} /> : <WifiOff size={15} />}{" "}
            {dbConnected
              ? "Database connected"
              : configured
                ? "Database unavailable"
                : "Database not configured"}
          </label>
          <button
            className="refresh"
            onClick={() => void refresh()}
            aria-label="Refresh database data"
            title="Refresh database data"
            disabled={busy}
          >
            <RefreshCw size={16} className={busy ? "spin" : ""} />
          </button>
        </header>
        <div className="content">
          <div className="heading">
            <div>
              <small>CAMPUS WORKSPACE</small>
              <h1>{title}</h1>
              <p>{descriptions[tab]}</p>
            </div>
          </div>
          {notice && (
            <div
              className={`notice ${notice.kind}`}
              role={notice.kind === "error" ? "alert" : "status"}
            >
              {notice.message}
              <button onClick={() => setNotice(null)}>Dismiss</button>
            </div>
          )}
          <div hidden={tab !== "attendance"}>
            <AttendanceWorkspace
              key={session.user.id}
              classes={classes}
              students={students}
              userId={session.user.id}
              notify={showNotice}
            />
          </div>
          {tab === "overview" && (
            <Overview
              classes={classes}
              students={students}
              teachers={teachers}
              connected={dbConnected}
              loading={busy}
              isAdmin={userRole === "administrator"}
              device={device}
              deviceError={deviceError}
              now={now}
              onNavigate={navigate}
            />
          )}
          {tab === "classes" && (
            <section className="panel">
              {userRole === "administrator" && (
                <>
                  <h2>Add a class</h2>
                  <p className="muted">
                    Create classes before assigning people.
                  </p>
                  <form onSubmit={addClass} className="form classform">
                    <label>
                      Class name
                      <input
                        required
                        value={classNameInput}
                        onChange={(e) => setClassNameInput(e.target.value)}
                        placeholder="e.g. CSE"
                      />
                    </label>
                    <label>
                      Section
                      <input
                        required
                        value={section}
                        onChange={(e) => setSection(e.target.value)}
                        placeholder="A"
                      />
                    </label>
                    <label>
                      Academic year
                      <input
                        value={year}
                        onChange={(e) => setYear(e.target.value)}
                        placeholder="2026-27"
                      />
                    </label>
                    <button
                      className="primary"
                      disabled={busy || userRole !== "administrator"}
                    >
                      <Plus size={16} /> Add class
                    </button>
                  </form>
                </>
              )}
              <h2 className="subhead">Available classes · {classes.length}</h2>
              <div
                className="tablewrap"
                tabIndex={0}
                role="region"
                aria-label="Records table, scroll horizontally on small screens"
              >
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Class</th>
                      <th scope="col">Section</th>
                      <th scope="col">Academic year</th>
                      <th scope="col">ID</th>
                      {userRole === "administrator" && <th scope="col">Action</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {classes.map((c) => (
                      <tr key={c.id}>
                        <td>{c.name}</td>
                        <td>{c.section}</td>
                        <td>{c.academic_year || "—"}</td>
                        <td>
                          <code>{c.id.slice(0, 8)}…</code>
                        </td>
                        {userRole === "administrator" && (
                          <td>
                            <button
                              className="outline danger"
                              onClick={() => void deleteClass(c)}
                              disabled={busy}
                            >
                              Delete
                            </button>
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {!classes.length && (
                <p className="empty">
                  {busy
                    ? "Loading classes…"
                    : userRole === "administrator"
                      ? "No classes yet. Create your first class above."
                      : "No assigned classes yet. Ask your administrator to assign one."}
                </p>
              )}
            </section>
          )}
          {(tab === "students" || tab === "teachers") && (
            <>
              {userRole === "administrator" && (
                <section className="panel">
                  <h2>
                    Register a {tab === "students" ? "student" : "teacher"}
                  </h2>
                  <p className="muted">
                    {tab === "students"
                      ? "Each student is assigned to one class."
                      : "Teachers can be assigned to multiple classes."}
                  </p>
                  <form
                    className="form"
                    onSubmit={(e) =>
                      void addPerson(
                        e,
                        tab === "students" ? "student" : "teacher",
                      )
                    }
                  >
                    <label>
                      Full name
                      <input
                        required
                        value={fullName}
                        onChange={(e) => setFullName(e.target.value)}
                        placeholder="Enter full name"
                      />
                    </label>
                    <label>
                      {tab === "students" ? "Roll number" : "Employee ID"}
                      <input
                        required
                        value={identifier}
                        onChange={(e) => setIdentifier(e.target.value)}
                        placeholder={
                          tab === "students" ? "e.g. 26CS001" : "e.g. EMP014"
                        }
                      />
                    </label>
                    {tab === "students" ? (
                      <label>
                        Assigned class
                        <select
                          required
                          value={studentClass}
                          onChange={(e) => setStudentClass(e.target.value)}
                        >
                          <option value="">Select class</option>
                          {classes.map((c) => (
                            <option key={c.id} value={c.id}>
                              {c.name}-{c.section} {c.academic_year || ""}
                            </option>
                          ))}
                        </select>
                      </label>
                    ) : (
                      <fieldset>
                        <legend>Assigned classes</legend>
                        {classes.length ? (
                          classes.map((c) => (
                            <label className="check" key={c.id}>
                              <input
                                type="checkbox"
                                checked={teacherClasses.includes(c.id)}
                                onChange={(e) =>
                                  setTeacherClasses((old) =>
                                    e.target.checked
                                      ? [...old, c.id]
                                      : old.filter((x) => x !== c.id),
                                  )
                                }
                              />
                              {c.name}-{c.section}
                            </label>
                          ))
                        ) : (
                          <small>Create a class first.</small>
                        )}
                      </fieldset>
                    )}
                    <button
                      className="primary"
                      disabled={
                        busy || userRole !== "administrator" || !classes.length
                      }
                    >
                      <Plus size={16} /> Register{" "}
                      {tab === "students" ? "student" : "teacher"}
                    </button>
                  </form>
                </section>
              )}
              <section className="panel">
                <div className="listhead">
                  <div>
                    <h2>Registered {tab}</h2>
                    <p className="muted">Search records and manage status.</p>
                    {tab === "students" &&
                      userRole === "administrator" &&
                      !terminalOnline && (
                        <p className="system-note">
                          Terminal offline — fingerprint enrollment is
                          unavailable.
                        </p>
                      )}
                  </div>
                  <label className="search">
                    <Search size={16} />
                    <input
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      placeholder="Search name, ID or class"
                      aria-label={`Search ${tab}`}
                    />
                  </label>
                </div>
                <div
                  className="tablewrap"
                  tabIndex={0}
                  role="region"
                  aria-label="Records table, scroll horizontally on small screens"
                >
                  <table>
                    <thead>
                      <tr>
                        <th scope="col">Name / ID</th>
                        <th scope="col">Role</th>
                        <th scope="col">Class assignment</th>
                        <th scope="col">Fingerprint status</th>
                        <th scope="col">Account</th>
                        {userRole === "administrator" && (
                          <th scope="col">Action</th>
                        )}
                      </tr>
                    </thead>
                    <tbody>
                      {list.map((p) => (
                        <tr key={p.id}>
                          <td>
                            <b>{p.full_name}</b>
                            <small className="block">
                              {p.roll_number || p.employee_id}
                            </small>
                          </td>
                          <td>{p.role}</td>
                          <td>
                            {p.role === "student"
                              ? p.classes
                                ? `${p.classes.name}-${p.classes.section}`
                                : "Unassigned"
                              : (assignments[p.id] || [])
                                  .map((id) => {
                                    const c = classes.find((x) => x.id === id);
                                    return c ? `${c.name}-${c.section}` : "";
                                  })
                                  .filter(Boolean)
                                  .join(", ") || "No classes"}
                          </td>
                          <td>
                            {(() => {
                              const status = enrollmentStatuses[p.id];
                              const enrollmentStatus =
                                status?.enrollment_status ||
                                p.fingerprint_status;
                              return (
                                <>
                                  <span className="fingerprint-status">
                                    {enrollmentStatus.replace("_", " ")}
                                    {status?.slot_id
                                      ? ` · Template #${status.slot_id}`
                                      : ""}
                                  </span>
                                  {p.role === "student" &&
                                    userRole === "administrator" &&
                                    enrollmentStatus !== "enrolled" && (
                                      <button
                                        className="outline"
                                        onClick={() =>
                                          void requestEnrollment(p)
                                        }
                                        disabled={
                                          busy ||
                                          ["in_progress", "delete_processing"].includes(enrollmentStatus) ||
                                          !terminalOnline
                                        }
                                        title={
                                          terminalOnline
                                            ? "Enroll fingerprint"
                                            : "Terminal offline"
                                        }
                                      >
                                        {enrollmentStatus === "failed"
                                          ? "Retry enrollment"
                                          : "Enroll fingerprint"}
                                      </button>
                                    )}
                                  {p.role === "student" &&
                                    userRole === "administrator" &&
                                    enrollmentStatus === "enrolled" && (
                                      <>
                                        <button
                                          className="outline danger"
                                          onClick={() => void requestFingerprintDeletion(p, "remove")}
                                          disabled={busy || !terminalOnline}
                                          title={terminalOnline ? "Remove fingerprint" : "Terminal offline"}
                                        >
                                          Delete fingerprint
                                        </button>
                                        <button
                                          className="outline"
                                          onClick={() => void requestFingerprintDeletion(p, "reenroll")}
                                          disabled={busy || !terminalOnline}
                                          title={terminalOnline ? "Remove the old template before enrolling again" : "Terminal offline"}
                                        >
                                          Re-enroll fingerprint
                                        </button>
                                      </>
                                    )}
                                  {enrollmentStatus === "delete_processing" && (
                                    <small className="block">Terminal is removing this template…</small>
                                  )}
                                  {enrollmentStatus === "delete_failed" && (
                                    <small className="block">Removal failed. The fingerprint remains enrolled.</small>
                                  )}
                                  {enrollmentStatus === "failed" &&
                                    status?.error_message && (
                                      <small className="block">
                                        {status.error_message}
                                      </small>
                                    )}
                                </>
                              );
                            })()}
                          </td>
                          <td>
                            <span className={p.active ? "active" : "inactive"}>
                              {p.active ? "Active" : "Inactive"}
                            </span>
                          </td>
                          {userRole === "administrator" && (
                            <td>
                              <div className="row-actions">
                                <button
                                  className="outline"
                                  onClick={() => void activeToggle(p)}
                                  disabled={busy}
                                >
                                  {p.active ? "Deactivate" : "Activate"}
                                </button>
                                <button
                                  className="outline danger"
                                  onClick={() =>
                                    void (p.role === "student"
                                      ? deleteStudent(p)
                                      : deleteTeacher(p))
                                  }
                                  disabled={
                                    busy ||
                                    (p.role === "student" && ["in_progress", "delete_processing"].includes(
                                      enrollmentStatuses[p.id]?.enrollment_status || "",
                                    ))
                                  }
                                >
                                  Delete
                                </button>
                              </div>
                            </td>
                          )}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {!list.length && (
                  <p className="empty">
                    {busy
                      ? "Loading records…"
                      : search
                        ? "No matches. Try a different name, ID, or class."
                        : `No ${tab} available yet.`}
                  </p>
                )}
              </section>
            </>
          )}
          <footer>
            CampusID · Connected campus prototype{" "}
            <span>
              Fingerprints stay on the sensor. Terminal integration is in
              progress.
            </span>
          </footer>
        </div>
      </main>
    </div>
  );
}
