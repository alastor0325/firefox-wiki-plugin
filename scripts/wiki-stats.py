#!/usr/bin/env python3
"""Full analysis of Firefox Knowledge Wiki usage.

Reads the wiki usage log (and, optionally, the triage decisions log) and
produces a meaningful report: overall hit rate, per-skill coverage and
hit rate, most/never consulted pages, ingest coverage, false-confidence
rate, and per-pattern correction rate.

Designed to be both a CLI (`--json` for machine output, default for a
human report) and an importable module: `compute_stats(...)` is pure and
unit-tested by tests/test-wiki-stats.py.

No third-party dependencies — stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


# ─── Loading ──────────────────────────────────────────────────────────

def load_jsonl(path: Path) -> tuple[list[dict], int]:
    """Return (events, n_malformed). Missing file → ([], 0)."""
    if not path.is_file():
        return [], 0
    events: list[dict] = []
    malformed = 0
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            malformed += 1
            continue
        if isinstance(obj, dict):
            events.append(obj)
        else:
            malformed += 1
    return events, malformed


def list_wiki_pages(wiki_path: Path) -> list[str]:
    """All wiki-relative .md page paths, excluding the log/report files."""
    if not wiki_path.is_dir():
        return []
    skip = {"usage-log.jsonl", "lint-log.json"}
    pages = []
    for p in wiki_path.rglob("*.md"):
        rel = str(p.relative_to(wiki_path))
        if rel in skip:
            continue
        pages.append(rel)
    return sorted(pages)


def _event_date(e: dict) -> str:
    return e.get("date") or e.get("ts") or ""


def _in_window(e: dict, since: str | None) -> bool:
    if not since:
        return True
    return _event_date(e)[:10] >= since


# ─── Core computation (pure, unit-tested) ─────────────────────────────

def compute_stats(
    events: list[dict],
    *,
    decisions: list[dict] | None = None,
    wiki_pages: list[str] | None = None,
    tracked_skills: list[str] | None = None,
    since: str | None = None,
) -> dict[str, Any]:
    """Compute every metric from the raw event list. Pure function."""
    decisions = decisions or []
    wiki_pages = wiki_pages or []
    tracked_skills = tracked_skills or []

    ev = [e for e in events if _in_window(e, since)]
    by_type: dict[str, list[dict]] = defaultdict(list)
    for e in ev:
        by_type[e.get("event_type", "")].append(e)

    pre = by_type.get("pre_lookup", [])
    reads = by_type.get("wiki_read", [])
    starts = by_type.get("session_start", [])
    ingests = by_type.get("ingest", [])

    # --- Overall hit rate ---
    hit_den = len(pre)
    hit_num = sum(1 for e in pre if e.get("wiki_hit") is True)
    overall_hit_rate = (hit_num / hit_den) if hit_den else None

    # --- Map instance_id -> set of wiki-event presence ---
    consulted_instances: set[str] = set()
    for e in pre + reads:
        iid = e.get("instance_id")
        if iid:
            consulted_instances.add(iid)

    # --- Per-skill coverage (from session_start instances) ---
    instances_by_skill: dict[str, list[str]] = defaultdict(list)
    for e in starts:
        skill = e.get("skill")
        iid = e.get("instance_id")
        if skill and iid:
            instances_by_skill[skill].append(iid)

    per_skill_coverage = {}
    for skill, iids in instances_by_skill.items():
        consulted = sum(1 for iid in iids if iid in consulted_instances)
        per_skill_coverage[skill] = {
            "instances": len(iids),
            "consulted": consulted,
            "coverage": consulted / len(iids) if iids else None,
        }
    # tracked skills with zero invocations
    for skill in tracked_skills:
        per_skill_coverage.setdefault(
            skill, {"instances": 0, "consulted": 0, "coverage": None}
        )

    # --- Per-skill hit rate (from pre_lookup tagged by skill) ---
    per_skill_hit: dict[str, dict] = {}
    null_skill_lookups = 0
    for e in pre:
        skill = e.get("skill")
        if not skill:
            null_skill_lookups += 1
            continue
        slot = per_skill_hit.setdefault(skill, {"consultations": 0, "hits": 0})
        slot["consultations"] += 1
        if e.get("wiki_hit") is True:
            slot["hits"] += 1
    for slot in per_skill_hit.values():
        c = slot["consultations"]
        slot["hit_rate"] = (slot["hits"] / c) if c else None

    # --- Most / never consulted pages ---
    reads_by_file: dict[str, dict] = {}
    for e in reads:
        f = e.get("file")
        if not f:
            continue
        slot = reads_by_file.setdefault(f, {"reads": 0, "last_read": ""})
        slot["reads"] += 1
        d = _event_date(e)
        if d > slot["last_read"]:
            slot["last_read"] = d
    most_consulted = sorted(
        ({"file": f, **v} for f, v in reads_by_file.items()),
        key=lambda r: (-r["reads"], r["file"]),
    )
    read_files = set(reads_by_file)
    never_consulted = [p for p in wiki_pages if p not in read_files]

    # --- Ingest coverage & false confidence ---
    n_ingest = len(ingests)
    bug_start_instances = len(instances_by_skill.get("bug-start", []))
    # The ratio is only meaningful once enough tracked bug-start runs exist;
    # historical ingests predate session_start tracking, so a tiny
    # denominator yields a nonsense percentage (e.g. 25/1).
    ingest_low_signal = bug_start_instances < 5
    ingest_coverage = (
        None if ingest_low_signal
        else n_ingest / bug_start_instances
    )
    from_wiki = [e for e in ingests if e.get("hypothesis_from_wiki") is True]
    fc_total = len(from_wiki)
    fc_wrong = sum(1 for e in from_wiki if e.get("hypothesis_correct") is False)
    fc_pending = [
        e.get("bug_id")
        for e in from_wiki
        if e.get("hypothesis_correct") is None
    ]
    fc_rate = (fc_wrong / fc_total) if fc_total else None

    # --- Per-pattern correction rate (join decisions-log) ---
    corrected_bugs: set[int] = set()
    for d in decisions:
        if d.get("event") == "apply-feedback" and d.get("bug_id") is not None:
            try:
                corrected_bugs.add(int(d["bug_id"]))
            except (TypeError, ValueError):
                pass
    # instance_id -> bug_id, from session_start args
    instance_bug: dict[str, int] = {}
    for e in starts:
        iid = e.get("instance_id")
        args = e.get("args")
        if not iid or not args:
            continue
        bug = _first_int(args)
        if bug is not None:
            instance_bug[iid] = bug
    # Backfill from the bug_id now tagged on pre_lookup/wiki_read events, for
    # sessions that never emitted a session_start (e.g. ad-hoc or hook-only
    # searches). session_start args win (inserted first); this fills empties.
    for e in pre + reads:
        iid = e.get("instance_id")
        bug = e.get("bug_id")
        if iid and bug is not None and iid not in instance_bug:
            try:
                instance_bug[iid] = int(bug)
            except (TypeError, ValueError):
                pass
    pattern_sessions: dict[str, set[str]] = defaultdict(set)
    pattern_corrected: dict[str, set[str]] = defaultdict(set)
    for e in reads:
        if e.get("skill") != "triage":
            continue
        f = e.get("file")
        iid = e.get("instance_id")
        if not f or not iid:
            continue
        pattern_sessions[f].add(iid)
        bug = instance_bug.get(iid)
        if bug is not None and bug in corrected_bugs:
            pattern_corrected[f].add(iid)
    per_pattern = []
    for f, sess in pattern_sessions.items():
        corr = len(pattern_corrected.get(f, set()))
        per_pattern.append({
            "pattern": f,
            "sessions": len(sess),
            "corrected": corr,
            "correction_rate": corr / len(sess) if sess else None,
        })
    per_pattern.sort(key=lambda r: (-(r["correction_rate"] or 0), r["pattern"]))

    # --- Direct wiki-use -> outcome join (bug-grained false confidence) ---
    # Of bugs whose code search hit the wiki, how many were later corrected by
    # a human (from the decisions log). Independent of ingest events, so it
    # works even when nothing was ingested for the bug.
    wiki_hit_bugs = {
        e["bug_id"] for e in pre
        if e.get("wiki_hit") is True and e.get("bug_id") is not None
    }
    wiki_hit_corrected = wiki_hit_bugs & corrected_bugs

    return {
        "window_since": since,
        "counts": {
            "pre_lookup": len(pre),
            "wiki_read": len(reads),
            "session_start": len(starts),
            "ingest": n_ingest,
        },
        "overall_hit_rate": {
            "lookups": hit_den,
            "hits": hit_num,
            "rate": overall_hit_rate,
        },
        "per_skill_coverage": per_skill_coverage,
        "per_skill_hit_rate": per_skill_hit,
        "null_skill_lookups": null_skill_lookups,
        "most_consulted": most_consulted,
        "never_consulted": never_consulted,
        "ingest_coverage": {
            "ingests": n_ingest,
            "bug_start_instances": bug_start_instances,
            "ratio": ingest_coverage,
            "low_signal": ingest_low_signal,
        },
        "false_confidence": {
            "from_wiki": fc_total,
            "wrong": fc_wrong,
            "rate": fc_rate,
            "pending_bug_ids": fc_pending,
        },
        "per_pattern_correction": per_pattern,
        "wiki_hit_outcome": {
            "bugs_with_wiki_hit": len(wiki_hit_bugs),
            "later_corrected": len(wiki_hit_corrected),
        },
        "has_decisions_log": bool(decisions),
    }


def _first_int(value: Any) -> int | None:
    """Extract the first integer from an args string/number (e.g. a bug id)."""
    if isinstance(value, int):
        return value
    if not isinstance(value, str):
        return None
    cur = ""
    for ch in value:
        if ch.isdigit():
            cur += ch
        elif cur:
            break
    return int(cur) if cur else None


# ─── Rendering ────────────────────────────────────────────────────────

def _pct(x: float | None) -> str:
    return "n/a" if x is None else f"{x * 100:.0f}%"


def _low_signal(n: int, threshold: int) -> str:
    return "  (low signal)" if n < threshold else ""


def render_report(s: dict[str, Any], malformed: int = 0) -> str:
    out: list[str] = []
    w = out.append
    win = f" since {s['window_since']}" if s["window_since"] else ""
    w(f"=== Firefox Wiki Usage Report{win} ===\n")

    c = s["counts"]
    w(f"Events: {c['pre_lookup']} pre_lookup, {c['wiki_read']} wiki_read, "
      f"{c['session_start']} session_start, {c['ingest']} ingest"
      + (f"  ({malformed} malformed lines skipped)" if malformed else ""))

    hr = s["overall_hit_rate"]
    w(f"\nOverall hit rate: {_pct(hr['rate'])} "
      f"({hr['hits']}/{hr['lookups']} code searches found wiki content)")

    # Per-skill coverage
    w("\n--- Per-Skill Coverage (was the wiki consulted during this skill?) ---")
    cov = s["per_skill_coverage"]
    if cov:
        w(f"{'Skill':<26} {'Instances':>9} {'Consulted':>9} {'Coverage':>9}")
        for skill in sorted(cov, key=lambda k: (-cov[k]['instances'], k)):
            v = cov[skill]
            w(f"{skill:<26} {v['instances']:>9} {v['consulted']:>9} "
              f"{_pct(v['coverage']):>9}{_low_signal(v['instances'], 5)}")
    else:
        w("(no session_start events yet)")

    # Per-skill hit rate
    w("\n--- Per-Skill Hit Rate (when consulted, did it find anything?) ---")
    phr = s["per_skill_hit_rate"]
    if phr:
        w(f"{'Skill':<26} {'Lookups':>8} {'Hits':>6} {'Hit Rate':>9}")
        for skill in sorted(phr, key=lambda k: (-phr[k]['consultations'], k)):
            v = phr[skill]
            w(f"{skill:<26} {v['consultations']:>8} {v['hits']:>6} "
              f"{_pct(v['hit_rate']):>9}{_low_signal(v['consultations'], 10)}")
    else:
        w("(no skill-tagged pre_lookup events yet)")
    if s["null_skill_lookups"]:
        w(f"({s['null_skill_lookups']} lookups had no active skill — excluded)")

    # Most consulted
    w("\n--- Most Consulted Pages (top 10) ---")
    mc = s["most_consulted"][:10]
    if mc:
        for r in mc:
            w(f"  {r['reads']:>3}x  {r['file']}  (last {r['last_read'][:10]})")
    else:
        w("(no wiki_read events yet)")

    # Never consulted
    nc = s["never_consulted"]
    w(f"\n--- Never Consulted Pages ({len(nc)}) ---")
    if nc:
        for p in nc[:20]:
            w(f"  {p}")
        if len(nc) > 20:
            w(f"  ... and {len(nc) - 20} more")
    else:
        w("(all pages have been read, or no wiki dir provided)")

    # Ingest coverage
    ic = s["ingest_coverage"]
    w("\n--- Ingest Coverage ---")
    if ic.get("low_signal"):
        w(f"  {ic['ingests']} ingests, {ic['bug_start_instances']} tracked "
          "bug-start runs — too few tracked runs for a meaningful ratio yet")
    else:
        w(f"  {ic['ingests']} ingests / {ic['bug_start_instances']} bug-start "
          f"runs = {_pct(ic['ratio'])}")

    # False confidence
    fc = s["false_confidence"]
    w("\n--- False Confidence Rate ---")
    if fc["from_wiki"]:
        w(f"  {fc['wrong']}/{fc['from_wiki']} wiki-sourced hypotheses were "
          f"wrong = {_pct(fc['rate'])}")
        if fc["pending_bug_ids"]:
            w(f"  pending hypothesis_correct: bugs "
              f"{', '.join(map(str, fc['pending_bug_ids']))}")
    else:
        w("  n/a (no ingests with hypothesis_from_wiki=true yet)")

    # Per-pattern correction
    w("\n--- Per-Pattern Correction Rate (triage) ---")
    if not s["has_decisions_log"]:
        w("  (no decisions-log.jsonl — skipped)")
    elif s["per_pattern_correction"]:
        w(f"{'Pattern':<44} {'Sessions':>8} {'Corrected':>9} {'Rate':>6}")
        for r in s["per_pattern_correction"]:
            w(f"{r['pattern']:<44} {r['sessions']:>8} {r['corrected']:>9} "
              f"{_pct(r['correction_rate']):>6}")
    else:
        w("  (no triage-tagged wiki reads joined to corrections yet)")

    # Wiki-hit outcome (bug-grained false confidence)
    if s["has_decisions_log"]:
        who = s["wiki_hit_outcome"]
        w("\n--- Wiki-Hit Outcome (did wiki-hit bugs get corrected?) ---")
        if who["bugs_with_wiki_hit"]:
            w(f"  {who['later_corrected']}/{who['bugs_with_wiki_hit']} bugs whose "
              "code search hit the wiki were later corrected by a human")
        else:
            w("  (no wiki-hit pre_lookup events carried a bug id yet)")

    # Recommendations
    w("\n--- Recommendations ---")
    for rec in _recommendations(s):
        w(f"  * {rec}")

    return "\n".join(out) + "\n"


def _recommendations(s: dict[str, Any]) -> list[str]:
    recs: list[str] = []
    hr = s["overall_hit_rate"]["rate"]
    if hr is not None and hr < 0.3 and s["overall_hit_rate"]["lookups"] >= 20:
        recs.append("Overall hit rate is low — wiki may lack content for the "
                    "topics being searched, or lookup isn't being triggered.")
    for skill, v in s["per_skill_coverage"].items():
        if v["instances"] >= 10 and (v["coverage"] or 0) < 0.3:
            recs.append(f"{skill}: <30% coverage over {v['instances']} runs — "
                        "wiki not in this skill's workflow or lacks its topics.")
    for skill, v in s["per_skill_hit_rate"].items():
        if v["consultations"] >= 10 and (v["hit_rate"] or 0) < 0.2:
            recs.append(f"{skill}: <20% hit rate over {v['consultations']} "
                        "lookups — add wiki pages for this skill's topics.")
    fc = s["false_confidence"]
    if fc["from_wiki"] >= 5 and (fc["rate"] or 0) > 0.1:
        recs.append("False-confidence rate >10% — run /firefox-wiki:verify; "
                    "some pages may be misleading investigations.")
    for r in s["per_pattern_correction"]:
        if r["sessions"] >= 8 and (r["correction_rate"] or 0) > 0.25:
            recs.append(f"Pattern {r['pattern']}: {_pct(r['correction_rate'])} "
                        "correction rate — re-verify or rewrite it.")
    if not recs:
        recs.append("Nothing urgent. Keep using the wiki and re-run monthly.")
    return recs


# ─── CLI ──────────────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Analyze Firefox wiki usage.")
    ap.add_argument("--wiki-path",
                    default=os.environ.get("WIKI_PATH",
                                           str(Path.home() / "firefox-wiki")))
    ap.add_argument("--decisions-log",
                    default=os.environ.get(
                        "DECISIONS_LOG",
                        str(Path.home() / "firefox-triage" / "decisions-log.jsonl")))
    ap.add_argument("--allowlist", default="",
                    help="Path to wiki-relevant-skills.txt (optional).")
    ap.add_argument("--since", default=None,
                    help="Only count events on/after this YYYY-MM-DD.")
    ap.add_argument("--json", action="store_true",
                    help="Emit machine-readable JSON instead of a report.")
    args = ap.parse_args(argv)

    wiki_path = Path(args.wiki_path).expanduser()
    log_path = wiki_path / "usage-log.jsonl"
    if not log_path.is_file():
        print(f"No usage log at {log_path}. Nothing to analyze.")
        return 1

    events, malformed = load_jsonl(log_path)
    decisions, _ = load_jsonl(Path(args.decisions_log).expanduser())
    wiki_pages = list_wiki_pages(wiki_path)

    tracked: list[str] = []
    allow = args.allowlist
    if not allow:
        cand = Path(__file__).parent / "wiki-relevant-skills.txt"
        if cand.is_file():
            allow = str(cand)
    if allow and Path(allow).is_file():
        tracked = [ln.strip() for ln in Path(allow).read_text().splitlines()
                   if ln.strip()]

    stats = compute_stats(events, decisions=decisions, wiki_pages=wiki_pages,
                          tracked_skills=tracked, since=args.since)

    if args.json:
        print(json.dumps(stats, indent=2))
    else:
        print(render_report(stats, malformed=malformed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
