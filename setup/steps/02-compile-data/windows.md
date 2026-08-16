# Step 2 on Windows

No elevation, no UAC, nothing for the owner to click. Everything is inside their
own home folder.

Create these three, copying the same `SKILL.md` into the first two:

    %USERPROFILE%\.claude\skills\compile-data\SKILL.md
    %USERPROFILE%\.codex\skills\compile-data\SKILL.md
    %USERPROFILE%\.codex\prompts\compile-data.md

Create parent folders as needed. If a file is already there, overwrite it —
this one is ours and carries no owner state.

**Do not restart Claude Code now.** The row is done the moment these files
exist. A restart only makes `/compile-data` appear in the menu, and that is
wanted at the end of the event - see `README.md`. Finish the checklist first.
