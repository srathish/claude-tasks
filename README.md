# claude-tasks

A bridge to send tasks from your phone to your laptop.

```
Phone (GitHub Pages form)  →  this repo (tasks/*.json)  →  Laptop poller  →  new project folder
```

## Parts
- **`docs/index.html`** — mobile form, served at https://srathish.github.io/claude-tasks/
- **`tasks/*.json`** — one file per task the phone submits
- **`poller.sh`** — runs every minute on the laptop: pulls, creates a project folder under
  `~/finding jobs/<slug>/` with a `TASK.md`, marks the task `received`, and shows a notification.

## Laptop control
```bash
launchctl list | grep claudetasks         # is the poller running?
tail -f ~/claude-tasks/poller.log         # watch activity
launchctl unload ~/Library/LaunchAgents/com.srathish.claudetasks.plist   # stop
launchctl load  ~/Library/LaunchAgents/com.srathish.claudetasks.plist    # start
```

## Phone setup (one time)
1. Open https://srathish.github.io/claude-tasks/ and add to Home Screen.
2. Create a GitHub **fine-grained token** scoped to `srathish/claude-tasks` with
   **Contents: Read and write**. Paste it into the form's Settings once.
