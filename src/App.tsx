import { useEffect, useMemo, useState, type FormEvent } from "react";
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
} from "lucide-react";
import { configured, configurationError, supabase } from "./lib/supabase";
import {
  caughtError,
  databaseError,
  validateClassInput,
  validatePersonInput,
} from "./lib/admin";
type Cls = {
  id: string;
  name: string;
  section: string;
  academic_year: string | null;
};
type Person = {
  id: string;
  full_name: string;
  role: "student" | "teacher";
  roll_number: string | null;
  employee_id: string | null;
  class_id: string | null;
  fingerprint_status: string;
  active: boolean;
  classes?: Cls | null;
};
type Tab = "overview" | "classes" | "students" | "teachers";
type Notice = {
  message: string;
  kind: "success" | "error";
};

export default function App() {
  const [tab, setTab] = useState<Tab>("overview"),
    [classes, setClasses] = useState<Cls[]>([]),
    [people, setPeople] = useState<Person[]>([]),
    [assignments, setAssignments] = useState<Record<string, string[]>>({}),
    [notice, setNotice] = useState<Notice | null>(null),
    [search, setSearch] = useState(""),
    [busy, setBusy] = useState(false),
    [dbConnected, setDbConnected] = useState(false);
  const [cn, setCn] = useState(""),
    [section, setSection] = useState("A"),
    [year, setYear] = useState("2026-27"),
    [name, setName] = useState(""),
    [code, setCode] = useState(""),
    [studentClass, setStudentClass] = useState(""),
    [teacherClasses, setTeacherClasses] = useState<string[]>([]);
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
  async function refresh() {
    if (!supabase) {
      setDbConnected(false);
      showNotice(
        configurationError || "Supabase is not configured.",
        "error",
      );
      return;
    }
    setBusy(true);
    try {
      const [c, p, a] = await Promise.all([
        supabase.from("classes").select("*").order("name"),
        supabase
          .from("people")
          .select("*")
          .order("created_at", { ascending: false }),
        supabase.from("teacher_classes").select("teacher_id,class_id"),
      ]);
      const err = c.error || p.error || a.error;
      if (err) {
        setDbConnected(false);
        showNotice(databaseError(err), "error");
        return;
      }
      setDbConnected(true);
      const classRows = (c.data || []) as Cls[];
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
    } catch (error) {
      setDbConnected(false);
      showNotice(caughtError(error), "error");
    } finally {
      setBusy(false);
    }
  }
  useEffect(() => {
    void refresh();
  }, []);
  async function addClass(e: FormEvent) {
    e.preventDefault();
    if (!supabase) return;
    const className = cn.trim();
    const classSection = section.trim();
    const validationError = validateClassInput(className, classSection);
    if (validationError) {
      showNotice(validationError, "error");
      return;
    }
    setBusy(true);
    try {
      const { error } = await supabase.from("classes").insert({
        name: className,
        section: classSection,
        academic_year: year.trim() || null,
      });
      if (error) {
        showNotice(databaseError(error), "error");
        return;
      }
      setCn("");
      showNotice("Class created.");
      await refresh();
    } catch (error) {
      showNotice(caughtError(error), "error");
    } finally {
      setBusy(false);
    }
  }
  async function addPerson(e: FormEvent, role: "student" | "teacher") {
    e.preventDefault();
    if (!supabase) return;
    const personName = name.trim();
    const identifier = code.trim();
    const validationError = validatePersonInput(
      role,
      personName,
      identifier,
      studentClass,
      teacherClasses,
    );
    if (validationError) {
      showNotice(validationError, "error");
      return;
    }
    setBusy(true);
    setNotice(null);
    try {
      if (role === "teacher") {
        const { error: teacherError } = await supabase.rpc(
          "register_teacher_with_classes",
          {
            p_full_name: personName,
            p_employee_id: identifier,
            p_class_ids: [...new Set(teacherClasses)],
          },
        );
        if (teacherError) {
          showNotice(databaseError(teacherError), "error");
          return;
        }
      } else {
        const { error } = await supabase.from("people").insert({
          full_name: personName,
          role,
          roll_number: identifier,
          employee_id: null,
          class_id: studentClass,
          fingerprint_status: "not_enrolled",
        });
        if (error) {
          showNotice(databaseError(error), "error");
          return;
        }
      }
      setName("");
      setCode("");
      setStudentClass("");
      setTeacherClasses([]);
      showNotice(
        `${role === "student" ? "Student" : "Teacher"} registered. Hardware enrollment is not connected yet.`,
      );
      await refresh();
    } catch (error) {
      showNotice(caughtError(error), "error");
    } finally {
      setBusy(false);
    }
  }
  async function activeToggle(p: Person) {
    if (!supabase) return;
    setBusy(true);
    try {
      const { error } = await supabase
        .from("people")
        .update({ active: !p.active })
        .eq("id", p.id);
      showNotice(
        error ? databaseError(error) : `${p.full_name} updated.`,
        error ? "error" : "success",
      );
      if (!error) await refresh();
    } catch (error) {
      showNotice(caughtError(error), "error");
    } finally {
      setBusy(false);
    }
  }
  const title =
    tab === "overview"
      ? "Overview"
      : tab === "classes"
        ? "Classes"
        : tab === "students"
          ? "Students"
          : "Teachers";
  const list = (tab === "students" ? students : teachers).filter((p) =>
    [
      p.full_name,
      p.roll_number || "",
      p.employee_id || "",
      p.classes?.name || "",
    ]
      .join(" ")
      .toLowerCase()
      .includes(search.toLowerCase()),
  );
  return (
    <div className="shell">
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
        {(
          [
            ["overview", "Overview", LayoutDashboard],
            ["classes", "Classes", BookOpen],
            ["students", "Students", GraduationCap],
            ["teachers", "Teachers", Users],
          ] as const
        ).map(([id, label, Icon]) => (
          <button
            key={id}
            className={"nav " + (tab === id ? "chosen" : "")}
            onClick={() => setTab(id)}
          >
            <Icon size={18} />
            {label}
          </button>
        ))}
        <div className="device">
          <span className="dot" />
          <div>
            <b>Fingerprint terminal</b>
            <small>ESP32 · R307</small>
          </div>
          <em>DEMO</em>
        </div>
        <div className="admin">
          <span>AD</span>
          <div>
            <b>Administrator</b>
            <small>Admin workspace</small>
          </div>
        </div>
      </aside>
      <main>
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
          <button className="refresh" onClick={() => void refresh()}>
            <RefreshCw size={16} />
          </button>
        </header>
        <div className="content">
          <div className="heading">
            <div>
              <small>ADMIN CONSOLE</small>
              <h1>{title}</h1>
              <p>Manage classes, people and fingerprint enrollment records.</p>
            </div>
          </div>
          {!configured && (
            <div className="banner">
              <ShieldCheck />
              <div>
                <b>Connect your Supabase database</b>
                <p>
                  Copy <code>.env.example</code> to <code>.env.local</code>, add
                  your project URL and public key, then restart Vite.
                </p>
              </div>
            </div>
          )}
          {notice && (
            <div className={`notice ${notice.kind}`}>
              {notice.message}
              <button onClick={() => setNotice(null)}>Dismiss</button>
            </div>
          )}
          {tab === "overview" && (
            <>
              <div className="stats">
                {[
                  [BookOpen, "Total classes", classes.length],
                  [GraduationCap, "Students", students.length],
                  [Users, "Teachers", teachers.length],
                  [
                    Fingerprint,
                    "Fingerprints enrolled",
                    people.filter((p) => p.fingerprint_status === "enrolled")
                      .length,
                  ],
                ].map(([I, l, v]: any) => (
                  <div className="stat" key={l}>
                    <I />
                    <small>{l}</small>
                    <strong>{v}</strong>
                    <p>Demo records</p>
                  </div>
                ))}
              </div>
              <div className="panel">
                <h2>Quick actions</h2>
                <p className="muted">Set up your demo in this order.</p>
                <div className="actions">
                  <button onClick={() => setTab("classes")}>
                    <BookOpen />
                    Create a class <span>→</span>
                  </button>
                  <button onClick={() => setTab("students")}>
                    <GraduationCap />
                    Register a student <span>→</span>
                  </button>
                  <button onClick={() => setTab("teachers")}>
                    <Users />
                    Register a teacher <span>→</span>
                  </button>
                </div>
                <h2>System checklist</h2>
                <p>{dbConnected ? "✓" : "○"} Supabase connection</p>
                <p>
                  {classes.length ? "✓" : "○"} Create classes ({classes.length})
                </p>
                <p>
                  {students.length && teachers.length ? "✓" : "○"} Register
                  students and teachers
                </p>
                <p>
                  ○ Connect real ESP32/R307 fingerprint enrollment (next step)
                </p>
              </div>
            </>
          )}
          {tab === "classes" && (
            <section className="panel">
              <h2>Add a class</h2>
              <p className="muted">Create classes before assigning people.</p>
              <form onSubmit={addClass} className="form classform">
                <label>
                  Class name
                  <input
                    required
                    value={cn}
                    onChange={(e) => setCn(e.target.value)}
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
                <button className="primary" disabled={busy || !configured}>
                  <Plus size={16} /> Add class
                </button>
              </form>
              <h2 className="subhead">All classes · {classes.length}</h2>
              <div className="tablewrap">
                <table>
                  <thead>
                    <tr>
                      <th>Class</th>
                      <th>Section</th>
                      <th>Academic year</th>
                      <th>ID</th>
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
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {!classes.length && (
                <p className="empty">
                  No classes yet. Create your first class above.
                </p>
              )}
            </section>
          )}
          {(tab === "students" || tab === "teachers") && (
            <>
              <section className="panel">
                <h2>Register a {tab === "students" ? "student" : "teacher"}</h2>
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
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      placeholder="Enter full name"
                    />
                  </label>
                  <label>
                    {tab === "students" ? "Roll number" : "Employee ID"}
                    <input
                      required
                      value={code}
                      onChange={(e) => setCode(e.target.value)}
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
                    disabled={busy || !configured || !classes.length}
                  >
                    <Plus size={16} /> Register{" "}
                    {tab === "students" ? "student" : "teacher"}
                  </button>
                </form>
              </section>
              <section className="panel">
                <div className="listhead">
                  <div>
                    <h2>Registered {tab}</h2>
                    <p className="muted">Search records and manage status.</p>
                  </div>
                  <label className="search">
                    <Search size={16} />
                    <input
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      placeholder="Search name, ID or class"
                    />
                  </label>
                </div>
                <div className="tablewrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Name / ID</th>
                        <th>Role</th>
                        <th>Class assignment</th>
                        <th>Fingerprint status</th>
                        <th>Account</th>
                        <th>Action</th>
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
                            <span className="fingerprint-status">
                              {p.fingerprint_status.replace("_", " ")}
                            </span>
                          </td>
                          <td>
                            <span className={p.active ? "active" : "inactive"}>
                              {p.active ? "Active" : "Inactive"}
                            </span>
                          </td>
                          <td>
                            <button
                              className="outline"
                              onClick={() => void activeToggle(p)}
                            >
                              {p.active ? "Deactivate" : "Activate"}
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {!list.length && <p className="empty">No records found.</p>}
              </section>
            </>
          )}
          <footer>
            CampusID demo prototype{" "}
            <span>
              Fingerprint templates remain in the R307 sensor; the database
              stores slot mappings.
            </span>
          </footer>
        </div>
      </main>
    </div>
  );
}
