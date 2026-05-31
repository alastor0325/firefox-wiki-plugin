#!/usr/bin/env python3
"""Unit tests for scripts/wiki-stats.py compute_stats().

Run: python3 tests/test-wiki-stats.py
Exits non-zero on any failure. No third-party deps.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import importlib.util

spec = importlib.util.spec_from_file_location(
    "wiki_stats", Path(__file__).parent.parent / "scripts" / "wiki-stats.py")
wiki_stats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wiki_stats)

compute_stats = wiki_stats.compute_stats
load_jsonl = wiki_stats.load_jsonl
_first_int = wiki_stats._first_int

PASS = 0
FAIL = 0


def check(desc, cond, detail=""):
    global PASS, FAIL
    if cond:
        print(f"PASS [{desc}]")
        PASS += 1
    else:
        print(f"FAIL [{desc}]{(': ' + detail) if detail else ''}")
        FAIL += 1


# ─── Fixture: a small but representative event stream ─────────────────
# Three bug-start runs (iid B1, B2, B3), one triage run (iid T1).
#   B1 consulted the wiki: one hit + one page read.
#   B2 consulted the wiki but only got a miss (pre_lookup, wiki_hit:false).
#     A miss still counts as "consulted" — the wiki WAS checked; the hit
#     rate (separate metric) captures that it found nothing.
#   B3 never touched the wiki at all (no wiki events) -> NOT consulted.
#   T1 read a triage pattern page; its bug (2042320) was corrected.
#   Plus 1 historical pre_lookup with no skill (skill:null).
# So bug-start: 3 instances, 2 consulted (B1,B2) -> 66.7% coverage.
EVENTS = [
    {"event_type": "session_start", "skill": "bug-start", "instance_id": "B1", "args": "2042862", "date": "2026-05-30T10:00:00Z"},
    {"event_type": "pre_lookup", "skill": "bug-start", "instance_id": "B1", "term": "AutoplayPolicy", "wiki_hit": True, "date": "2026-05-30T10:01:00Z"},
    {"event_type": "wiki_read", "skill": "bug-start", "instance_id": "B1", "file": "components/AutoplayPolicy.md", "date": "2026-05-30T10:01:30Z"},

    {"event_type": "session_start", "skill": "bug-start", "instance_id": "B2", "args": "2040167", "date": "2026-05-30T11:00:00Z"},
    {"event_type": "pre_lookup", "skill": "bug-start", "instance_id": "B2", "term": "Nonexistent", "wiki_hit": False, "date": "2026-05-30T11:01:00Z"},

    {"event_type": "session_start", "skill": "bug-start", "instance_id": "B3", "args": "2050000", "date": "2026-05-30T11:30:00Z"},

    {"event_type": "session_start", "skill": "triage", "instance_id": "T1", "args": "2042320", "date": "2026-05-30T12:00:00Z"},
    {"event_type": "wiki_read", "skill": "triage", "instance_id": "T1", "file": "triage/chrome-ua.md", "date": "2026-05-30T12:01:00Z"},

    {"event_type": "pre_lookup", "skill": None, "instance_id": None, "term": "OldSearch", "wiki_hit": False, "date": "2026-05-29T09:00:00Z"},

    {"event_type": "ingest", "bug_id": 2042862, "hypothesis_from_wiki": True, "hypothesis_correct": False, "date": "2026-05-30T13:00:00Z"},
    {"event_type": "ingest", "bug_id": 2040167, "hypothesis_from_wiki": True, "hypothesis_correct": True, "date": "2026-05-30T13:05:00Z"},
    {"event_type": "ingest", "bug_id": 9999999, "hypothesis_from_wiki": False, "hypothesis_correct": None, "date": "2026-05-30T13:10:00Z"},
]
DECISIONS = [
    {"event": "apply-feedback", "bug_id": 2042320, "ts": "2026-05-31T09:00:00Z"},
]
WIKI_PAGES = [
    "components/AutoplayPolicy.md",   # read
    "triage/chrome-ua.md",            # read
    "components/NeverRead.md",        # never read
    "components/AlsoNeverRead.md",    # never read
]
TRACKED = ["bug-start", "triage", "verify"]

s = compute_stats(EVENTS, decisions=DECISIONS, wiki_pages=WIKI_PAGES,
                  tracked_skills=TRACKED)

# ─── Overall hit rate: 3 pre_lookup, 1 hit ───────────────────────────
check("overall hit rate counts", s["overall_hit_rate"]["lookups"] == 3
      and s["overall_hit_rate"]["hits"] == 1,
      detail=str(s["overall_hit_rate"]))
check("overall hit rate value ~33%",
      abs(s["overall_hit_rate"]["rate"] - 1/3) < 1e-9)

# ─── Per-skill coverage ──────────────────────────────────────────────
cov = s["per_skill_coverage"]
check("bug-start: 3 instances, 2 consulted (hit+miss count; no-event doesn't)",
      cov["bug-start"]["instances"] == 3 and cov["bug-start"]["consulted"] == 2,
      detail=str(cov["bug-start"]))
check("bug-start coverage = 2/3",
      abs(cov["bug-start"]["coverage"] - 2/3) < 1e-9)
check("triage: 1 instance, 1 consulted",
      cov["triage"]["instances"] == 1 and cov["triage"]["consulted"] == 1)
check("tracked-but-unused skill shows 0 instances",
      cov["verify"]["instances"] == 0 and cov["verify"]["coverage"] is None)

# ─── Per-skill hit rate ──────────────────────────────────────────────
phr = s["per_skill_hit_rate"]
check("bug-start hit rate: 2 lookups, 1 hit -> 50%",
      phr["bug-start"]["consultations"] == 2
      and phr["bug-start"]["hits"] == 1
      and phr["bug-start"]["hit_rate"] == 0.5,
      detail=str(phr["bug-start"]))
check("null-skill lookups excluded and counted",
      s["null_skill_lookups"] == 1 and "null" not in phr and None not in phr)

# ─── Most / never consulted ──────────────────────────────────────────
mc_files = [r["file"] for r in s["most_consulted"]]
check("most consulted includes both read pages",
      "components/AutoplayPolicy.md" in mc_files
      and "triage/chrome-ua.md" in mc_files)
check("never consulted = the two unread pages",
      set(s["never_consulted"]) == {"components/NeverRead.md",
                                     "components/AlsoNeverRead.md"},
      detail=str(s["never_consulted"]))

# ─── Ingest coverage: low signal (only 2 tracked bug-start) ──────────
ic = s["ingest_coverage"]
check("ingest coverage low-signal guarded",
      ic["low_signal"] is True and ic["ratio"] is None
      and ic["ingests"] == 3 and ic["bug_start_instances"] == 3,
      detail=str(ic))

# ─── False confidence: 2 from-wiki, 1 wrong -> 50% ───────────────────
fc = s["false_confidence"]
check("false confidence: 1/2 wrong = 50%",
      fc["from_wiki"] == 2 and fc["wrong"] == 1 and fc["rate"] == 0.5,
      detail=str(fc))
check("false confidence pending list empty (no nulls among from_wiki)",
      fc["pending_bug_ids"] == [])

# ─── Per-pattern correction: T1 read chrome-ua, bug 2042320 corrected ─
pp = {r["pattern"]: r for r in s["per_pattern_correction"]}
check("pattern chrome-ua: 1 session, 1 corrected -> 100%",
      pp["triage/chrome-ua.md"]["sessions"] == 1
      and pp["triage/chrome-ua.md"]["corrected"] == 1
      and pp["triage/chrome-ua.md"]["correction_rate"] == 1.0,
      detail=str(pp.get("triage/chrome-ua.md")))

# ─── _first_int helper ───────────────────────────────────────────────
check("_first_int from '2042862 --triage-mode'",
      _first_int("2042862 --triage-mode") == 2042862)
check("_first_int from int", _first_int(2042320) == 2042320)
check("_first_int from None", _first_int(None) is None)
check("_first_int from non-numeric", _first_int("--force") is None)

# ─── Empty input doesn't crash ───────────────────────────────────────
empty = compute_stats([], decisions=[], wiki_pages=[], tracked_skills=[])
check("empty input: hit rate None",
      empty["overall_hit_rate"]["rate"] is None)
check("empty input: no decisions log flag",
      empty["has_decisions_log"] is False)

# ─── Malformed-line tolerance in load_jsonl ──────────────────────────
import tempfile
import os
tmp = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
tmp.write('{"event_type":"pre_lookup","wiki_hit":true}\n')
tmp.write('{ this is not json\n')
tmp.write('\n')
tmp.write('42\n')  # valid json but not a dict
tmp.write('{"event_type":"wiki_read","file":"x.md"}\n')
tmp.close()
evs, malformed = load_jsonl(Path(tmp.name))
os.unlink(tmp.name)
check("load_jsonl keeps 2 dict events", len(evs) == 2, detail=str(evs))
check("load_jsonl counts 2 malformed (bad json + non-dict)", malformed == 2,
      detail=str(malformed))

# ─── since-window filter ─────────────────────────────────────────────
windowed = compute_stats(EVENTS, since="2026-05-30")
check("since filter drops the 2026-05-29 null lookup",
      windowed["overall_hit_rate"]["lookups"] == 2
      and windowed["null_skill_lookups"] == 0,
      detail=str(windowed["overall_hit_rate"]))

print(f"\nResults: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
