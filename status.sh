#!/bin/bash
# Shows the status of all phone-submitted tasks, newest first.
REPO_DIR="/Users/saiyeeshrathish/claude-tasks"
cd "$REPO_DIR" || exit 1
git pull --quiet --no-rebase origin main >/dev/null 2>&1

/usr/bin/python3 - <<'PY'
import json, glob, os
from datetime import datetime, timezone

files = sorted(glob.glob("tasks/*.json"), reverse=True)
ICON = {"done":"✅ done    ", "building":"🔨 building ", "received":"⏳ queued  ",
        "pending":"🕓 waiting "}

if not files:
    print("No tasks yet.")
else:
    print(f"\n  {'STATUS':<12} {'PROJECT':<34} {'WHEN':<10} LINK")
    print("  " + "-"*78)
    for fp in files:
        try: d = json.load(open(fp))
        except: continue
        st = ICON.get(d.get("status",""), "•  "+str(d.get("status","")))
        title = (d.get("title","") or os.path.basename(fp))[:33]
        when = ""
        try:
            t = datetime.fromisoformat(d["created"].replace("Z","+00:00"))
            s = (datetime.now(timezone.utc) - t).total_seconds()
            when = "just now" if s<60 else f"{int(s//60)}m ago" if s<3600 else f"{int(s//3600)}h ago" if s<86400 else f"{int(s//86400)}d ago"
        except: pass
        url = d.get("repo_url","") or ""
        print(f"  {st:<12} {title:<34} {when:<10} {url}")
    print()
PY
