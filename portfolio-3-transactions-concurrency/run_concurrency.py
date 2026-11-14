#!/usr/bin/env python3
"""
MIT 8103 - Portfolio 3, Part B: concurrency scenario runner.

Each scenario in scenarios/ has two session scripts (sNN_name_A.sql and
sNN_name_B.sql) and a check script (sNN_name_check.sql). The runner:
  1. resets the database to seed.sql,
  2. starts session A, then session B after its "-- start_after:" delay,
     each in its own psql process (= its own database connection),
  3. timestamps every NOTICE (from log()) and ERROR line as it arrives,
  4. runs the check script to show the final state,
  5. writes results/sNN_name.txt and results/summary.md.

Standard library + psql only. Connection from PG* environment variables, e.g.
    export PGHOST=localhost PGUSER=postgres PGDATABASE=laguna_p3
Usage:
    python3 run_concurrency.py            # all scenarios
    python3 run_concurrency.py s03        # just one
"""
import glob, os, re, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
SCEN = os.path.join(HERE, "scenarios")
RESULTS = os.path.join(HERE, "results")


def psql_run(sql, aligned=True):
    args = ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1"] + ([] if aligned else ["-t", "-A"])
    out = subprocess.run(args, input=sql, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"psql failed:\n{out.stderr}")
    return out.stdout


def header(path, key, default=""):
    m = re.search(rf"^-- {key}:\s*(.*)$", open(path, encoding="utf-8").read(), re.M)
    return m.group(1).strip() if m else default


class Session(threading.Thread):
    def __init__(self, name, path, t0):
        super().__init__()
        self.name_, self.path, self.t0 = name, path, t0
        self.delay = float(header(path, "start_after", "0"))
        self.role = header(path, "session", name)
        self.events = []          # (seconds since t0, text)

    def run(self):
        time.sleep(self.delay)
        sql = open(self.path, encoding="utf-8").read()
        p = subprocess.Popen(["psql", "-X", "-q", "-t", "-A"], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        p.stdin.write(sql)
        p.stdin.close()
        for line in p.stderr:                     # notices and errors arrive here, unbuffered
            t = time.monotonic() - self.t0
            line = line.rstrip()
            if line.startswith("NOTICE:"):
                self.events.append((t, line[len("NOTICE:"):].strip()))
            elif line.startswith(("ERROR:", "DETAIL:", "WARNING:")):
                self.events.append((t, line))
        p.stdout.read()
        p.wait()


def run_scenario(prefix):
    a = glob.glob(os.path.join(SCEN, f"{prefix}_*_A.sql"))[0]
    name = os.path.basename(a)[:-6]
    b, check = a[:-6] + "_B.sql", a[:-6] + "_check.sql"
    title, expect = header(a, "title"), header(a, "expect")

    psql_run(open(os.path.join(HERE, "seed.sql")).read())
    t0 = time.monotonic()
    sessions = [Session("A", a, t0), Session("B", b, t0)]
    for s in sessions:
        s.start()
    for s in sessions:
        s.join()
    final = psql_run(open(check, encoding="utf-8").read())

    events = sorted((t, s.name_, msg) for s in sessions for t, msg in s.events)
    lines = [f"Scenario : {name}", f"Title    : {title}", f"Expected : {expect}", ""]
    for s in sessions:
        lines.append(f"Session {s.name_}: {s.role} (starts at +{s.delay:.1f}s)")
    lines += ["", "Timeline (seconds since start)", "-" * 78]
    for t, who, msg in events:
        pad = "" if who == "A" else " " * 30
        lines.append(f"+{t:5.2f}s  {who} | {pad}{msg}")
    lines += ["-" * 78, "", "Final state (check script):", final]
    text = "\n".join(lines)
    os.makedirs(RESULTS, exist_ok=True)
    open(os.path.join(RESULTS, f"{name}.txt"), "w").write(text)
    print(text)
    verdict = [l for l in final.splitlines() if "RESULT" in l]
    return name, title, expect, (verdict[0].strip(" |") if verdict else "")


if __name__ == "__main__":
    prefixes = sys.argv[1:] or sorted({os.path.basename(f)[:3] for f in glob.glob(os.path.join(SCEN, "s*_A.sql"))})
    rows = [run_scenario(p) for p in prefixes]
    if not sys.argv[1:]:
        md = ["| Scenario | What it shows | Expected | Observed |", "|---|---|---|---|"]
        md += [f"| {n} | {t} | {e} | {v.replace('RESULT:', '').strip()} |" for n, t, e, v in rows]
        open(os.path.join(RESULTS, "summary.md"), "w").write("\n".join(md) + "\n")
        print("\n".join(md))
