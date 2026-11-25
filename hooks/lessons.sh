#!/usr/bin/env bash
# Lessons: look them up, and propose new ones (as a PR Golden merges).
#
#   lessons.sh index                       titles of all lessons (printed at session start)
#   lessons.sh search "<error or topic>"   best-matching lessons, full text
#   lessons.sh propose <proposals.json>    add proposals on a branch in the agent-kit repo,
#                                          push it, and print the branch to open a PR from
#   lessons.sh announce <pr-url>           post each proposed lesson to #lessons with the PR link
#
# proposals.json: [{"type":"fixes|working-style","title":"","symptom":"","cause":"","fix":"","source":""}]
#
# Where the kit lives: the agent-kit repo itself, or a clone at $AGENT_KIT_DIR / ../agent-kit
# (attach agent-kit to the session). The vendored .agent-kit/ copy is used read-only for search.
source "$(dirname "$0")/lib.sh"
set -u

KIT_SELF="$(cd "$HOOK_DIR/.." && pwd)"
kit_repo() {
  # The writable agent-kit clone, if any.
  for d in "${AGENT_KIT_DIR:-}" "$PROJECT_DIR" "$(dirname "$PROJECT_DIR")/agent-kit" "$KIT_SELF"; do
    [ -n "$d" ] && [ -f "$d/install.sh" ] && [ -d "$d/.git" ] && { echo "$d"; return 0; }
  done
  return 1
}
lessons_dir() {
  local k; k="$(kit_repo)" && [ -d "$k/lessons" ] && { echo "$k/lessons"; return; }
  echo "$KIT_SELF/lessons"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  index)
    d="$(lessons_dir)"
    grep -h -E '^### L-[0-9]+' "$d"/*.md "$d"/playbooks/*.md 2>/dev/null | sed -E 's/^### //' || true
    ;;

  search)
    q="${*:-}"; [ -z "$q" ] && { echo "usage: lessons.sh search \"<text>\"" >&2; exit 2; }
    d="$(lessons_dir)"
    python3 - "$d" "$q" <<'PY'
import re, sys, pathlib
d, q = pathlib.Path(sys.argv[1]), sys.argv[2].lower()
stop = {"the","and","with","that","this","from","when","then","into","have","does","not","for","are","was"}
words = {w for w in re.findall(r"[a-z0-9_.-]{3,}", q) if w not in stop}
entries = []
for f in sorted(d.glob("*.md")) + sorted((d / "playbooks").glob("*.md")):
    for block in re.split(r"(?m)^(?=### L-\d+)", f.read_text()):
        if block.startswith("### L-"):
            text = block.lower()
            score = sum(3 if w in text.split("\n")[0] else 1 for w in words if w in text)
            if score:
                entries.append((score, block.strip()))
entries.sort(key=lambda e: -e[0])
if not entries:
    print("No matching lessons. Debug from scratch; if you solve it, propose a lesson at /report.")
for _, b in entries[:3]:
    print(b + "\n")
PY
    ;;

  propose)
    f="${1:-}"; [ -f "$f" ] || { echo "usage: lessons.sh propose <proposals.json>" >&2; exit 2; }
    k="$(kit_repo)" || { echo "LESSONS FAILED: agent-kit repo not reachable. Attach skylaryoshimitsu-blip/agent-kit to this session, then rerun." >&2; exit 1; }

    # Client safety: block lessons that mention the client's name, repo, or domain.
    prof="$PROJECT_DIR/agent-profile.yaml"
    if [ -f "$prof" ] && grep -qE '^\s*type:\s*client' "$prof"; then
      terms="$(grep -E '^\s*(name|display_name|github|production_url):' "$prof" | sed -E 's/^[^:]+:\s*//; s/#.*//; s/["'"'"']//g' \
        | tr '/' '\n' | sed -E 's#^https?:##; s/^\s+|\s+$//g' | grep -vE '^$|^(main|none)$' | awk 'length($0)>=4' | sort -u)"
      hits="$(printf '%s\n' "$terms" | while read -r t; do [ -n "$t" ] && grep -qiF -- "$t" "$f" && echo "$t"; done)"
      if [ -n "$hits" ]; then
        echo "LESSONS BLOCKED: proposals mention client details: $(echo $hits). Generalize them and rerun." >&2
        exit 1
      fi
    fi

    stem="$(date -u +%Y-%m-%d)-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    out="$(python3 - "$k/lessons" "$f" <<'PY'
import json, re, sys, pathlib
d, props = pathlib.Path(sys.argv[1]), json.load(open(sys.argv[2]))
ids = [int(m) for p in d.rglob("*.md") for m in re.findall(r"(?m)^### L-(\d+)", p.read_text())]
n = max(ids, default=0)
added = []
for p in props:
    kind = "working-style" if p.get("type") == "working-style" else "fixes"
    n += 1
    lid = f"L-{n:03d}"
    labels = ("When", "Why", "Do") if kind == "working-style" else ("Symptom", "Root cause", "Fix")
    entry = (f"\n### {lid} · {p['title'].strip()}\n"
             f"- **{labels[0]}:** {p['symptom'].strip()}\n"
             f"- **{labels[1]}:** {p['cause'].strip()}\n"
             f"- **{labels[2]}:** {p['fix'].strip()}\n"
             f"- **Source:** {p.get('source', '').strip()}\n")
    with open(d / f"{kind}.md", "a") as fh:
        fh.write(entry)
    added.append({"id": lid, "type": kind, **p})
print(json.dumps(added))
PY
)" || exit 1
    mkdir -p "$PROJECT_DIR/.agent"; printf '%s\n' "$out" > "$PROJECT_DIR/.agent/lessons-proposed.json"

    cur="$(git -C "$k" rev-parse --abbrev-ref HEAD)"
    if [ "$k" = "$PROJECT_DIR" ]; then
      branch="$cur"            # in the kit repo itself: commit on the session's branch
    else
      branch="lessons/$stem"
      git -C "$k" checkout -q -b "$branch"
    fi
    git -C "$k" add lessons
    git -C "$k" commit -qm "Propose lessons: $(printf '%s' "$out" | jq -r 'map(.id + " " + .title) | join("; ")')" || exit 1
    if git -C "$k" push -q -u origin "$branch" 2>/dev/null; then :
    elif [ "$k" != "$PROJECT_DIR" ] && git -C "$k" push -q origin "HEAD:refs/heads/$(branch_name)" 2>/dev/null; then
      branch="$(branch_name)"
    else
      echo "LESSONS FAILED: could not push lessons branch to agent-kit" >&2; exit 1
    fi
    [ "$k" != "$PROJECT_DIR" ] && git -C "$k" checkout -q "$cur"
    echo "Proposed $(printf '%s' "$out" | jq length) lesson(s) on agent-kit branch: $branch"
    echo "Next: open a PR on skylaryoshimitsu-blip/agent-kit from $branch into main, then run: lessons.sh announce <pr-url>"
    ;;

  announce)
    url="${1:-}"; [ -z "$url" ] && { echo "usage: lessons.sh announce <pr-url>" >&2; exit 2; }
    p="$PROJECT_DIR/.agent/lessons-proposed.json"; [ -f "$p" ] || { echo "no proposals found" >&2; exit 1; }
    jq -c '.[]' "$p" | while read -r l; do
      post lessons "💡 **Lesson proposal $(jq -r .id <<<"$l")** ($(jq -r .type <<<"$l")) — $(jq -r .title <<<"$l")
**$( [ "$(jq -r .type <<<"$l")" = working-style ] && echo When || echo Symptom ):** $(jq -r .symptom <<<"$l")
**$( [ "$(jq -r .type <<<"$l")" = working-style ] && echo Why || echo 'Root cause' ):** $(jq -r .cause <<<"$l")
**$( [ "$(jq -r .type <<<"$l")" = working-style ] && echo Do || echo Fix ):** $(jq -r .fix <<<"$l")
Approve = merge the PR · Edit = edit it in the PR · Reject = delete it from the PR (or close the PR)
$url"
    done
    ;;

  *) sed -n '2,14p' "$0"; exit 2 ;;
esac
