#!/bin/bash
# Polls srathish/claude-tasks for new tasks sent from the phone form.
# For each new "pending" task: creates a project folder, drops in TASK.md,
# marks the task "received" (pushed back so the phone sees it), and notifies.
# Mode: prepare + notify (you open Claude Code to actually build it).

set -uo pipefail

REPO_DIR="/Users/saiyeeshrathish/claude-tasks"        # this repo (the bridge)
PROJECTS_DIR="/Users/saiyeeshrathish/finding jobs"      # where new project folders are created
LOG="$REPO_DIR/poller.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

cd "$REPO_DIR" || { log "cannot cd to repo"; exit 1; }

# Pull latest tasks from GitHub
git pull --quiet --no-rebase origin main >> "$LOG" 2>&1 || { log "git pull failed"; exit 0; }

shopt -s nullglob
new_count=0

for f in tasks/*.json; do
  base="$(basename "$f")"
  marker="$REPO_DIR/.processed/$base"
  [ -f "$marker" ] && continue   # already handled locally

  status="$(/usr/bin/python3 -c "import json,sys; print(json.load(open('$f')).get('status',''))" 2>/dev/null)"
  [ "$status" != "pending" ] && { touch "$marker"; continue; }

  title="$(/usr/bin/python3 -c "import json; print(json.load(open('$f')).get('title','task'))" 2>/dev/null)"
  desc="$(/usr/bin/python3 -c "import json; print(json.load(open('$f')).get('description',''))" 2>/dev/null)"

  # slugify the title for a folder name
  slug="$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-50)"
  [ -z "$slug" ] && slug="task"
  dest="$PROJECTS_DIR/$slug"
  # avoid clobbering an existing folder
  if [ -e "$dest" ]; then dest="${dest}-$(date '+%H%M%S')"; fi

  mkdir -p "$dest"
  {
    echo "# $title"
    echo
    echo "_Task sent from phone on $(date '+%Y-%m-%d %H:%M')._"
    echo
    echo "## What Claude should do"
    echo
    echo "$desc"
  } > "$dest/TASK.md"

  log "created project: $dest (from $base)"
  touch "$marker"
  new_count=$((new_count+1))

  # Mark the task received in the repo so the phone can see status
  /usr/bin/python3 - "$f" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["status"] = "received"
json.dump(d, open(p, "w"), indent=2)
PY
  git add "$f" >> "$LOG" 2>&1
  git commit -q -m "received: $title" >> "$LOG" 2>&1
  git push -q origin main >> "$LOG" 2>&1 || log "push of status failed (will retry next run)"

  # macOS notification
  /usr/bin/osascript -e "display notification \"$title\" with title \"New task → ${slug}\" sound name \"Glass\"" 2>/dev/null
done

[ "$new_count" -gt 0 ] && log "done: $new_count new task(s)"
exit 0
