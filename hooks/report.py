#!/usr/bin/env python3
"""Session and weekly reports for agent-kit.

  report.py data                     -> print this session's facts (JSON) for the agent
  report.py build <report.json>      -> merge facts + agent-written content, write PDF,
                                        print the Discord message; paths in .agent/out.json
  report.py weekly [YYYY-MM-DD]      -> weekly rollup from the archive for this project
                                        (week containing the date; default: this week)

Times come from the hook log (.agent/session-log.jsonl), never from estimates.
"""
import json, os, re, subprocess, sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

def _project_dir():
    if os.environ.get("CLAUDE_PROJECT_DIR"):
        return Path(os.environ["CLAUDE_PROJECT_DIR"])
    try:
        top = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], stderr=subprocess.DEVNULL, text=True).strip()
        if top:
            return Path(top)
    except Exception:
        pass
    kit = Path(__file__).resolve().parent.parent
    return kit.parent if kit.name == ".agent-kit" else kit

PROJECT = _project_dir()
AGENT = PROJECT / ".agent"
LOG = AGENT / "session-log.jsonl"
ARCHIVE = Path(os.environ.get("AGENT_REPORTS_DIR", PROJECT.parent / "agent-reports"))
IDLE = 15 * 60  # gaps longer than this are not counted as hands-on time


# ---------- helpers ----------
def profile():
    """Read the few profile keys we need without a YAML dependency."""
    p = PROJECT / "agent-profile.yaml"
    text = p.read_text() if p.exists() else ""
    def key(name, default=""):
        m = re.search(rf"^\s*{name}:\s*([^#\n]+)", text, re.M)
        return m.group(1).strip().strip("'\"") if m else default
    hours = key("hours_per_week", "")
    return {
        "project_id": key("project_id", PROJECT.name),
        "display_name": key("display_name", PROJECT.name),
        "owner": key("name", ""),
        "timezone": key("timezone", "Asia/Manila"),
        "audience": key("audience", "non-technical"),
        "hours_per_week": float(hours) if hours else None,
    }

def parse(ts):
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)

def events():
    if not LOG.exists():
        return []
    out = []
    for line in LOG.read_text().splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out

def fmt_dur(secs):
    if secs is None:
        return "not measured this session (hooks didn't run)"
    secs = int(round(secs))
    return f"{secs // 3600}h {secs % 3600 // 60:02d}m"

def local(dt, tz):
    return dt.astimezone(ZoneInfo(tz)).strftime("%a %b %-d, %-I:%M %p")


# ---------- session facts ----------
def session_facts(now=None):
    now = now or datetime.now(timezone.utc)
    ev = events()
    starts = [e for e in ev if e.get("type") == "session_start"]
    prof = profile()
    if not starts:
        # Hooks didn't run this session (see lesson L-003): report without times.
        sys.stderr.write("WARNING: no session start in .agent/session-log.jsonl — hooks didn't run "
                         "(lesson L-003). Times will show as not measured.\n")
        return {
            "session": "u-" + now.strftime("%H%M%S"), "measured": False,
            "project_id": prof["project_id"], "project": prof["display_name"], "owner": prof["owner"],
            "timezone": prof["timezone"], "audience": prof["audience"], "hours_per_week": prof["hours_per_week"],
            "start_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "end_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "start_local": local(now, prof["timezone"]), "end_local": local(now, prof["timezone"]),
            "agent_seconds": None, "hands_on_seconds": None, "messages": None,
            "commits": [], "pushes": [], "prs": [],
        }
    sid = starts[-1]["session"]
    mine = sorted((e for e in ev if e.get("session") == sid), key=lambda e: e["at"])

    prompts = [parse(e["at"]) for e in mine if e["type"] == "prompt"]
    ends = [parse(e["at"]) for e in mine if e["type"] == "turn_end"]

    # Agent run time: each prompt until the agent's next turn_end (or now, for this turn).
    agent = 0.0
    for p in prompts:
        nxt = next((t for t in ends if t >= p), now)
        agent += (nxt - p).total_seconds()

    # Hands-on time: from the agent finishing a turn to Golden's next message
    # (reading, reviewing, approving), skipping idle gaps over 15 minutes.
    hands = 0.0
    for p in prompts[1:]:
        prev = max((t for t in ends if t <= p), default=None)
        if prev is not None:
            gap = (p - prev).total_seconds()
            if 0 < gap <= IDLE:
                hands += gap

    start = parse(next(e["at"] for e in mine if e["type"] == "session_start"))
    return {
        "session": sid,
        "measured": True,
        "project_id": prof["project_id"],
        "project": prof["display_name"],
        "owner": prof["owner"],
        "timezone": prof["timezone"],
        "audience": prof["audience"],
        "hours_per_week": prof["hours_per_week"],
        "start_utc": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "end_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "start_local": local(start, prof["timezone"]),
        "end_local": local(now, prof["timezone"]),
        "agent_seconds": round(agent),
        "hands_on_seconds": round(hands),
        "messages": len(prompts),
        "commits": [{"sha": e["sha"], "branch": e["branch"], "subject": e.get("subject", "")}
                    for e in mine if e["type"] == "commit"],
        "pushes": [{"sha": e["sha"], "branch": e["branch"]} for e in mine if e["type"] == "push"],
        "prs": [e["url"] for e in mine if e["type"] == "pr_opened"],
    }


# ---------- rendering ----------
TIME_NOTE = ("Agent run time: time the AI agent spent working on requests. "
             "Hands-on time: time between the agent finishing and Golden's next message "
             "(reviewing, testing, approving), excluding gaps over 15 minutes. "
             "Both are measured automatically from session timestamps.")

def same_day_end(r):
    s, e = r['start_local'].split(', '), r['end_local'].split(', ')
    return e[-1] if s[0] == e[0] else r['end_local']

def discord_text(r):
    when = (f"{r['start_local']} – {same_day_end(r)} ({r['timezone']})" if r.get("measured", True)
            else f"{r['end_local']} ({r['timezone']}) — session times not measured")
    lines = [f"**Work Report — {r['project']}**", when, ""]
    def section(title, items):
        if items:
            lines.append(f"**{title}**")
            lines.extend(f"• {i}" for i in items)
            lines.append("")
    section("Completed (verified)", [f"{c['task']}" + (f" — {c['proof']}" if c.get("proof") else "")
                                     for c in r.get("completed", [])])
    section("In progress", r.get("in_progress", []))
    section("Needs input / blocked", r.get("blocked", []))
    links = [f"{l['label']}: {l['url']}" for l in r.get("links", [])]
    section("Proof", links)
    lines.append("**Time**")
    lines.append(f"• Hands-on (Golden): {fmt_dur(r['hands_on_seconds'])}")
    lines.append(f"• Agent run time: {fmt_dur(r['agent_seconds'])}")
    lines.append("")
    section("Next session", r.get("next", []))
    lines.append("Full report attached (PDF).")
    return "\n".join(lines).strip()

def ensure_reportlab():
    try:
        import reportlab  # noqa: F401
    except ImportError:
        for extra in ([], ["--break-system-packages"]):
            if subprocess.call([sys.executable, "-m", "pip", "install", "-q", "--user", "reportlab", *extra],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
                break
        import site, importlib
        sys.path.append(site.getusersitepackages())
        importlib.invalidate_caches()

def write_pdf(path, title, subtitle, sections, footnote):
    ensure_reportlab()
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import inch
    from reportlab.lib import colors
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, ListFlowable, ListItem
    from xml.sax.saxutils import escape

    ss = getSampleStyleSheet()
    body = ParagraphStyle("b", parent=ss["BodyText"], fontSize=11, leading=15)
    h1 = ParagraphStyle("h1", parent=ss["Title"], fontSize=18, alignment=0, spaceAfter=4)
    sub = ParagraphStyle("s", parent=body, textColor=colors.HexColor("#555555"))
    h2 = ParagraphStyle("h2", parent=ss["Heading2"], fontSize=13, spaceBefore=12, spaceAfter=4)
    small = ParagraphStyle("sm", parent=body, fontSize=9, leading=12, textColor=colors.HexColor("#666666"))

    story = [Paragraph(escape(title), h1), Paragraph(escape(subtitle), sub), Spacer(1, 6)]
    for heading, items in sections:
        if not items:
            continue
        story.append(Paragraph(escape(heading), h2))
        story.append(ListFlowable([ListItem(Paragraph(escape(i), body), leftIndent=12) for i in items],
                                  bulletType="bullet", start="•", leftIndent=14))
    story += [Spacer(1, 14), Paragraph(escape(footnote), small)]
    SimpleDocTemplate(str(path), pagesize=letter, leftMargin=0.9 * inch, rightMargin=0.9 * inch,
                      topMargin=0.8 * inch, bottomMargin=0.8 * inch, title=title).build(story)


def build(report_path):
    content = json.loads(Path(report_path).read_text())
    r = {**session_facts(), **{k: v for k, v in content.items() if v is not None}}
    day = r["end_utc"][:10]
    stem = f"{day}-{r['session'][:8]}"
    AGENT.mkdir(exist_ok=True)
    pdf = AGENT / f"report-{stem}.pdf"
    data = AGENT / f"report-{stem}.json"
    sections = [
        ("Completed (verified)", [c["task"] + (f" — {c['proof']}" if c.get("proof") else "")
                                  for c in r.get("completed", [])]),
        ("In progress", r.get("in_progress", [])),
        ("Needs input / blocked", r.get("blocked", [])),
        ("Proof", [f"{l['label']}: {l['url']}" for l in r.get("links", [])]),
        ("Time", [f"Hands-on (Golden): {fmt_dur(r['hands_on_seconds'])}",
                  f"Agent run time: {fmt_dur(r['agent_seconds'])}"]),
        ("Next session", r.get("next", [])),
    ]
    write_pdf(pdf, f"Work Report — {r['project']}",
              f"{r['start_local']} – {r['end_local']}  ({r['timezone']})", sections, TIME_NOTE)
    data.write_text(json.dumps(r, indent=2))
    out = {"pdf": str(pdf), "json": str(data), "project_id": r["project_id"], "stem": stem,
           "message": discord_text(r)}
    (AGENT / "out.json").write_text(json.dumps(out, indent=2))
    print(out["message"])


# ---------- weekly ----------
def weekly(date_str=None):
    prof = profile()
    tz = ZoneInfo(prof["timezone"])
    ref = datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=tz) if date_str else datetime.now(tz)
    monday = (ref - timedelta(days=ref.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    sunday_end = monday + timedelta(days=7)
    folder = ARCHIVE / "reports" / prof["project_id"]
    rows = []
    for f in sorted(folder.glob("*.json")):
        r = json.loads(f.read_text())
        end = parse(r["end_utc"]).astimezone(tz)
        if monday <= end < sunday_end:
            rows.append(r)
    hands = sum(r["hands_on_seconds"] or 0 for r in rows)
    agent = sum(r["agent_seconds"] or 0 for r in rows)
    unmeasured = sum(1 for r in rows if not r.get("measured", True))
    done = [c["task"] for r in rows for c in r.get("completed", [])]
    open_items = rows[-1].get("in_progress", []) + rows[-1].get("blocked", []) if rows else []
    week_label = f"Week of {monday.strftime('%b %-d')} – {(sunday_end - timedelta(days=1)).strftime('%b %-d, %Y')}"
    target = prof["hours_per_week"]
    time_lines = [f"Hands-on (Golden): {fmt_dur(hands)}", f"Agent run time: {fmt_dur(agent)}",
                  f"Sessions: {len(rows)}" + (f" ({unmeasured} without measured time)" if unmeasured else "")]
    if target:
        time_lines.insert(1, f"Contract target: {target:g}h per week (hands-on so far: {hands / 3600:.1f}h)")
    AGENT.mkdir(exist_ok=True)
    pdf = AGENT / f"weekly-{monday.strftime('%Y-%m-%d')}.pdf"
    write_pdf(pdf, f"Weekly Report — {prof['display_name']}", f"{week_label} ({prof['timezone']})",
              [("Completed this week (verified)", done), ("Open items", open_items), ("Time", time_lines)],
              TIME_NOTE)
    msg = "\n".join([f"**Weekly Report — {prof['display_name']}**", week_label, "",
                     "**Completed this week**", *([f"• {d}" for d in done] or ["• (none recorded)"]), "",
                     "**Time**", *[f"• {t}" for t in time_lines], "", "Full report attached (PDF)."])
    (AGENT / "out.json").write_text(json.dumps({"pdf": str(pdf), "message": msg}, indent=2))
    print(msg)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "data":
        print(json.dumps(session_facts(), indent=2))
    elif cmd == "build" and len(sys.argv) > 2:
        build(sys.argv[2])
    elif cmd == "weekly":
        weekly(sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        print(__doc__)
        sys.exit(2)
