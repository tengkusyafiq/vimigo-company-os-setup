# Step 2 on Windows

No elevation, no UAC, nothing for the owner to click. Everything is inside their
own home folder.

Create these three, copying the same `SKILL.md` into the first two:

    %USERPROFILE%\.claude\skills\compile-data\SKILL.md
    %USERPROFILE%\.codex\skills\compile-data\SKILL.md
    %USERPROFILE%\.codex\prompts\compile-data.md

Create parent folders as needed. If a file is already there, overwrite it —
this one is ours and carries no owner state.

Then start a new Claude Code session, or the command will not appear.
