#!/bin/bash
# Polls srathish/claude-tasks for tasks sent from the phone form.
# FULLY AUTO: builds new projects, or CONTINUES existing ones (continue_of),
# optionally publishes to GitHub, pushes status back, and notifies.

set -uo pipefail

REPO_DIR="/Users/saiyeeshrathish/claude-tasks"        # this repo (the bridge)
PROJECTS_DIR="/Users/saiyeeshrathish/finding jobs"      # where project folders live
GH_USER="srathish"
LOG="$REPO_DIR/poller.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" 2>/dev/null; }
jget() { /usr/bin/python3 -c "import json; print(json.load(open('$1')).get('$2', '$3'))" 2>/dev/null; }
setstatus() {  # $1=file $2=key=val pairs via python
  /usr/bin/python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for kv in sys.argv[2:]:
    if "=" in kv:
        k, v = kv.split("=", 1); d[k] = v
json.dump(d, open(p, "w"), indent=2)
PY
}
pushstatus() { git add "$1" >> "$LOG" 2>&1; git commit -q -m "$2" >> "$LOG" 2>&1; git push -q origin main >> "$LOG" 2>&1 || log "status push failed"; }

cd "$REPO_DIR" || { log "cannot cd to repo"; exit 1; }
git pull --quiet --no-rebase origin main >> "$LOG" 2>&1 || { log "git pull failed"; exit 0; }

shopt -s nullglob
for f in tasks/*.json; do
  base="$(basename "$f")"
  marker="$REPO_DIR/.processed/$base"
  [ -f "$marker" ] && continue
  [ "$(jget "$f" status '')" != "pending" ] && { touch "$marker"; continue; }
  touch "$marker"   # claim immediately

  title="$(jget "$f" title task)"
  desc="$(jget "$f" description '')"
  publish="$(jget "$f" publish True)"
  visibility="$(jget "$f" visibility public)"
  continue_of="$(jget "$f" continue_of '')"
  [ "$visibility" = "private" ] && vis_flag="--private" || vis_flag="--public"

  # ---- decide: continue an existing project, or build a new one ----
  if [ -n "$continue_of" ] && [ -d "$PROJECTS_DIR/$continue_of" ]; then
    mode="continue"; dest="$PROJECTS_DIR/$continue_of"; slug="$continue_of"
  else
    mode="new"
    slug="$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-50)"
    [ -z "$slug" ] && slug="task"
    dest="$PROJECTS_DIR/$slug"; reponame="$slug"
    if [ -e "$dest" ]; then ts="$(date '+%H%M%S')"; dest="${dest}-${ts}"; reponame="${slug}-${ts}"; fi
    mkdir -p "$dest"
    { echo "# $title"; echo; echo "_From phone on $(date '+%Y-%m-%d %H:%M')._"; echo;
      echo "## What Claude should do"; echo; echo "$desc"; } > "$dest/TASK.md"
  fi

  log "START $mode: $dest (from $base)"
  notify "Claude: $slug" "$([ "$mode" = continue ] && echo 'Continuing…' || echo 'Building…')"
  setstatus "$f" "status=building"; pushstatus "$f" "building: $title"

  # ---- run Claude headless ----
  if [ "$mode" = "continue" ]; then
    { echo; echo "## Follow-up ($(date '+%Y-%m-%d %H:%M'))"; echo; echo "$desc"; } >> "$dest/TASK.md"
    prompt="This project already exists. TASK.md has a new '## Follow-up' section at the bottom. Continue the work per those new instructions. Keep existing files, modify what's needed, update README.md if relevant. When done, stop."
    ( cd "$dest" && claude --continue -p "$prompt" --dangerously-skip-permissions > .claude-build.log 2>&1 ) \
      || ( cd "$dest" && claude -p "$prompt" --dangerously-skip-permissions > .claude-build.log 2>&1 )
  else
    prompt="Read TASK.md in this directory and fully build the project it describes. Create all files here. Add a README.md explaining what it is and how to run it. When finished, stop."
    ( cd "$dest" && claude -p "$prompt" --dangerously-skip-permissions > .claude-build.log 2>&1 )
  fi
  log "claude finished: $dest"

  # ---- commit the result ----
  ( cd "$dest" && rm -f .claude-build.log
    [ -d .git ] || { git init -q && git branch -M main; }
    git add -A
    git -c user.email="saieagle@gmail.com" -c user.name="$GH_USER" commit -q -m "$([ "$mode" = continue ] && echo "Continue: $title" || echo "Build: $title")" ) >> "$LOG" 2>&1 || true

  # ---- publish / push ----
  repo_url=""
  if git -C "$dest" remote get-url origin >/dev/null 2>&1; then
    if ( cd "$dest" && git push -q origin HEAD:main ) >> "$LOG" 2>&1; then
      repo_url="$(git -C "$dest" remote get-url origin | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##')"
      log "pushed updates: $repo_url"
    fi
  elif [ "$publish" = "True" ]; then
    if ( cd "$dest" && gh repo create "$reponame" $vis_flag --source=. --remote=origin --push ) >> "$LOG" 2>&1; then
      repo_url="https://github.com/$GH_USER/$reponame"; log "published ($visibility): $repo_url"
    else
      log "gh repo create failed for $reponame"
    fi
  else
    log "publish=off — local only at $dest"
  fi

  # ---- if it's a published public website, enable GitHub Pages and grab the live URL ----
  pages_url=""
  if [ -n "$repo_url" ] && [ "$visibility" != "private" ]; then
    rname="$(basename "$repo_url")"
    pages_path=""
    if [ -f "$dest/index.html" ]; then pages_path="/"
    elif [ -f "$dest/docs/index.html" ]; then pages_path="/docs"; fi
    if [ -n "$pages_path" ]; then
      gh api -X POST "repos/$GH_USER/$rname/pages" -f "source[branch]=main" -f "source[path]=$pages_path" >> "$LOG" 2>&1 || true
      pages_url="https://$GH_USER.github.io/$rname/"
      log "pages enabled: $pages_url"
    fi
  fi

  # ---- mark done (remember folder so the phone can 'Continue') ----
  setstatus "$f" "status=done" "repo_url=$repo_url" "local_path=$(basename "$dest")" "pages_url=$pages_url"
  pushstatus "$f" "done: $title"

  if [ -n "$pages_url" ]; then notify "🌐 Live: $slug" "$pages_url"; log "DONE: $title -> $pages_url"
  elif [ -n "$repo_url" ]; then notify "✅ Done: $slug" "$repo_url"; log "DONE: $title -> $repo_url"
  elif [ "$publish" = "True" ]; then notify "⚠️ Built locally: $slug" "Publish failed — $dest"
  else notify "✅ Built locally: $slug" "Not published — $dest"; fi
done

exit 0
