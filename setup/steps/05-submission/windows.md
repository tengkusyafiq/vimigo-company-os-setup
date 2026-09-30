# Step 5 on Windows

The same `node` commands in the README do the whole step. This page only
says where things tend to be.

- **Their Second Brain:** `%USERPROFILE%\Second Brain`. Write the document
  and `Submission\files\` there, never in Documents, Desktop or OneDrive.
- **Their conversations:** `node lib/wrapup-read.js list --since "<opensAt>"`
  already finds Claude Code (`%USERPROFILE%\.claude\projects`), Codex
  (`%USERPROFILE%\.codex\sessions`) and Cowork (under `%APPDATA%\Claude` or
  the Store app's own folder). Use its list rather than looking yourself.
- **Files they may have made:** the folders their notes or conversations
  name; otherwise Desktop, Downloads and Documents, and screenshots in
  `Pictures\Screenshots`. Only files from the event days that belong to the
  project.
- **Google files they downloaded:** `%USERPROFILE%\Downloads`. A browser
  set to save elsewhere puts them there instead; look only in Downloads.
- **OneDrive:** a file there can be "online only" — a cloud icon, no real
  bytes on this computer. Copying it makes Windows download it first. If it
  will not copy, leave it out and name it in the list instead.
- **Copy with your own file tools**, keeping the original where it is. A path
  with spaces needs quotes in any command.
- Company names can hold characters a Windows file name cannot (`\ / : * ? "
  < > |`). `verify.js` already gives the safe file name in `"file"` — use it
  exactly; the title inside the document keeps the real name.
