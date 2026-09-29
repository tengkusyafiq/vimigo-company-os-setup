# Step 3 on macOS

`lib/scheduler.js install` registers a launch agent named
`com.vimigo.second-brain-sync`, which runs every two minutes in the background.
macOS may show a Login Items notice that something was added — that is this
agent, and there is nothing to click.

It lives entirely in the owner's home folder; nothing here needs administrator
rights. If it cannot be registered, try once more, then block the row as the
README says — the Second Brain folder still works locally either way.
