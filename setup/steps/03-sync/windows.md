# Step 3 on Windows

`lib/scheduler.js install` registers a Task Scheduler task named
`Second Brain Sync`. It runs regularly through `wscript.exe`, hidden —
no window, nothing to click, and it never asks for administrator rights.

If a company policy blocks Task Scheduler entirely, `install` fails outright.
Try it once more, then block the row as the README says. The Second Brain
folder still works locally either way — only the copy to Vimigo is affected.
