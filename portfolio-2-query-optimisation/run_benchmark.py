#!/usr/bin/env python3
"""
MIT 8103 - Portfolio 2: query benchmark
Runs each query in a .sql file (split on "-- @Qn" markers) through psql,
saves its result rows and its EXPLAIN (ANALYZE, BUFFERS) plan, and records
the median execution time of 5 runs (after 1 warm-up run).

Uses only the Python standard library + the psql command-line client.
Connection settings come from the usual PG* environment variables, e.g.
    export PGHOST=localhost PGUSER=postgres PGDATABASE=laguna_care

Usage:
    python3 run_benchmark.py <phase-name> <queries.sql>
    python3 run_benchmark.py --compare            # build results/comparison.md
"""
import csv, os, re, statistics, subprocess, sys

RUNS = 5
HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")
PHASES = ["1-baseline", "2-indexed", "3-optimised"]


def psql(sql):
    out = subprocess.run(
        ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-P", "pager=off"],
        input="SET search_path TO hospital;\n" + sql, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"psql failed:\n{out.stderr}")
    return out.stdout


def load_queries(path):
    text = open(path, encoding="utf-8").read()
    parts = re.split(r"^-- @(Q\d+) (.*)$", text, flags=re.M)
    # parts = [header, id, title, body, id, title, body, ...]
    return [(parts[i], parts[i + 1].strip(), parts[i + 2].strip().rstrip(";"))
            for i in range(1, len(parts), 3)]


def run_phase(phase, path):
    outdir = os.path.join(RESULTS, phase)
    os.makedirs(outdir, exist_ok=True)
    rows = []
    for qid, title, sql in load_queries(path):
        # strip comment lines so EXPLAIN gets a clean statement
        body = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
        with open(os.path.join(outdir, f"{qid}_result.txt"), "w") as f:
            f.write(psql(body + ";"))
        times, plan = [], ""
        for i in range(RUNS + 1):                      # run 0 is a warm-up
            plan = psql(f"EXPLAIN (ANALYZE, BUFFERS) {body};")
            t = float(re.search(r"Execution Time: ([\d.]+) ms", plan).group(1))
            if i > 0:
                times.append(t)
        with open(os.path.join(outdir, f"{qid}_plan.txt"), "w") as f:
            f.write(f"-- {qid}: {title}\n-- phase: {phase}\n\n{body};\n\n{plan}")
        med = statistics.median(times)
        rows.append([qid, title, f"{med:.3f}", " ".join(f"{t:.3f}" for t in times)])
        print(f"{phase:12} {qid:3} {med:10.3f} ms  {title}")
    with open(os.path.join(outdir, "summary.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["query", "title", "median_ms", "all_runs_ms"])
        w.writerows(rows)


def compare():
    data = {}
    for p in PHASES:
        with open(os.path.join(RESULTS, p, "summary.csv")) as f:
            for r in csv.DictReader(f):
                data.setdefault(r["query"], {"title": r["title"]})[p] = float(r["median_ms"])
    lines = ["| Query | Task | Baseline (ms) | + Indexes (ms) | + Rewrite (ms) | Speed-up | Same result? |",
             "|---|---|---:|---:|---:|---:|:---:|"]
    for q, d in data.items():
        base, best = d[PHASES[0]], d[PHASES[2]]
        same = open(os.path.join(RESULTS, PHASES[0], f"{q}_result.txt")).read() == \
               open(os.path.join(RESULTS, PHASES[2], f"{q}_result.txt")).read()
        lines.append(f"| {q} | {d['title']} | {base:,.2f} | {d[PHASES[1]]:,.2f} | {best:,.2f} | "
                     f"{base / best:,.0f}x | {'yes' if same else 'NO'} |")
    md = "\n".join(lines) + "\n"
    open(os.path.join(RESULTS, "comparison.md"), "w").write(md)
    print(md)


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--compare":
        compare()
    elif len(sys.argv) == 3:
        run_phase(sys.argv[1], sys.argv[2])
    else:
        sys.exit(__doc__)
