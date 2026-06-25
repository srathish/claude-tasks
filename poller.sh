#!/bin/bash
# Polls srathish/claude-tasks for tasks sent from the phone form.
# FULLY AUTO mode: for each new "pending" task it
#   1. creates a project folder + TASK.md
#   2. runs Claude Code headless to build the project
#   3. creates a GitHub repo for it and pushes
#   4. marks the task "done" with the repo URL (pushed back so the phone sees it)
#   5. notifies you with the GitHub link

set -uo pipefail

REPO_DIR="/Users/saiyeeshrathish/claude-tasks"        # this repo (the bridge)
PROJECTS_DIR="/Users/saiyeeshrathish/finding jobs"      # where new project folders are created
GH_USER="srathish"
LOG="$REPO_DIR/poller.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" 2>/dev/null; }

cd "$REPO_DIR" || { log "cannot cd to repo"; exit 1; }

git pull --quiet --no-rebase origin main >> "$LOG" 2>&1 || { log "git pull failed"; exit 0; }

shopt -s nullglob
for f in tasks/*.json; do
  base="$(basename "$f")"
  marker="$REPO_DIR/.processed/$base"
  [ -f "$marker" ] && continue

  status="$(/usr/bin/python3 -c "import json; print(json.load(open('$f')).get('status',''))" 2>/dev/null)"
  [ "$status" != "pending" ] && { touch "$marker"; continue; }

  # Claim it immediately so overlapping runs don't double-build
  touch "$marker"

  title="$(/usr/bin/python3 -c "import json; print(json.load(open('$f')).get('title','task'))" 2>/dev/null)"
  desc="$(/usr/bin/python3 -c "import json; print(json.load(open('$f')).get('description',''))" 2>/dev/null)"

  slug="$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-50)"
  [ -z "$slug" ] && slug="task"
  dest="$PROJECTS_DIR/$slug"
  reponame="$slug"
  if [ -e "$dest" ]; then ts="$(date '+%H%M%S')"; dest="${dest}-${ts}"; reponame="${slug}-${ts}"; fi

  mkdir -p "$dest"
  {
    echo "# $title"; echo
    echo "_Task sent from phone on $(date '+%Y-%m-%d %H:%M')._"; echo
    echo "## What Claude should do"; echo
    echo "$desc"
  } > "$dest/TASK.md"

  log "START build: $dest (from $base)"
  notify "Claude is building: $slug" "Started — I'll ping you when it's done."

  # Push a "building" status so the phone shows it live
  /usr/bin/python3 - "$f" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["status"] = "building"
json.dump(d, open(p, "w"), indent=2)
PY
  git add "$f" >> "$LOG" 2>&1
  git commit -q -m "building: $title" >> "$LOG" 2>&1
  git push -q origin main >> "$LOG" 2>&1 || log "building-status push failed"

  # 1) Build with Claude Code, headless and autonomous
  build_log="$dest/.claude-build.log"
  ( cd "$dest" && claude -p "Read TASK.md in this directory and fully build the project it describes. Create all files here. Add a README.md explaining what it is and how to run it. When finished, stop." \
      --dangerously-skip-permissions > "$build_log" 2>&1 )
  log "build finished: $dest"

  # 2) Init git + commit the result
  ( cd "$dest" \
      && rm -f .claude-build.log \
      && git init -q \
      && git branch -M main \
      && git add -A \
      && git -c user.email="saieagle@gmail.com" -c user.name="$GH_USER" commit -q -m "Build: $title (via phone task)" ) >> "$LOG" 2>&1

  # 3) Create the GitHub repo and push
  repo_url=""
  if ( cd "$dest" && gh repo create "$reponame" --public --source=. --remote=origin --push ) >> "$LOG" 2>&1; then
    repo_url="https://github.com/$GH_USER/$reponame"
    log "pushed: $repo_url"
  else
    log "gh repo create failed for $reponame (folder built locally at $dest)"
  fi

  # 4) Mark the task done with the link, push status back
  /usr/bin/python3 - "$f" "$repo_url" <<'PY'
import json, sys
p, url = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["status"] = "done"
d["repo_url"] = url
d["local_path"] = sys.argv[0] if False else d.get("local_path","")
json.dump(d, open(p, "w"), indent=2)
PY
  git add "$f" >> "$LOG" 2>&1
  git commit -q -m "done: $title" >> "$LOG" 2>&1
  git push -q origin main >> "$LOG" 2>&1 || log "status push failed (retry next run)"

  # 5) Ping with the link
  if [ -n "$repo_url" ]; then
    notify "✅ Done: $slug" "$repo_url"
    log "DONE: $title -> $repo_url"
  else
    notify "⚠️ Built locally: $slug" "Push failed — see $dest"
  fi
done

exit 0
