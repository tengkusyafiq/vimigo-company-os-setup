Before anything else — this applies to every file in this setup, not only
this one:

If you cannot run commands on this computer at all, stop and reply only:

> *"This needs to run in Claude Code or Codex, not here. In the Claude app,
> click **Code**. Or open the **Codex** app. Then paste the same message
> there."*

Then run one command to see which operating system your commands actually
run on — `uname -s` with a shell tool, or
`[System.Environment]::OSVersion.Platform` with PowerShell only:

    uname -s

If it says `Linux`, you are inside a sandbox (for example Claude Cowork), not
on their Windows or Mac computer. Stop and reply with the same sentence
above. Participants' computers are only Windows or macOS — never Linux.

---

# vimigo ai setup — wrap-up (last session)

You are finishing a Vimigo event for this person: refresh the tree, check,
write their AI Workflow Submission into their Second Brain with the files
that show their work, send, and say one line. When session 1 never ran on
this laptop, set up what it would have first, exactly as `START.md` does —
the name question, the quiet `sync` row and the install steps all belong to
that file — and write up their week before the submission. This session
never sets up Zo.

§0 through §4 below are `START.md`'s own §0 through §4, **verbatim**. Keep
them identical if either file changes; a laptop with no Node yet needs §1
exactly as much here as it does there.

## 0. Put the setup on this computer

One command decides how this goes:

    node --version

**If it answers, let the shipped downloader do the work.** It reads
`files.json` — the list of everything this setup needs — and pulls the whole
tree down for you. Fetch that one file to
`<home>/.vimigo/setup/lib/fetch-setup.js` first:

    https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/lib/fetch-setup.js

then run it, and skip to step 1:

    node lib/fetch-setup.js https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/

**If it does not answer**, Node is missing — step 1 installs it — so do this
part by hand. Fetch this:

    https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/files.json

It is an object with one key, **not a bare array**:

```json
{ "files": ["MASTER.md", "START.md", "lib/state.js", "steps/01-runtimes/README.md"] }
```

Read `files.json`'s `files` list. Fetch each entry from
`https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/<path>`
and write it to `<home>/.vimigo/setup/<path>`, keeping the folders.

**Use your own tools for this — the ones you use to read a web page and write a
file.** Do not shell out to `curl`, `wget`, or `Invoke-WebRequest`: on a real
machine `curl` was intercepted by a plugin and never reached the network, and
the improvised fallback that followed guessed the shape above wrong and crashed.

**Overwrite whatever is already there. Every file, every time.** A folder that
already exists means a previous run, and a previous run means older
instructions — quite possibly the ones with the fault somebody has since fixed.
Skipping a file because it is present is how a machine keeps running a version
nobody can reach.

**You never need git for this**, either way, and the by-hand path needs nothing
installed at all — which is the point of having one. Both git and Node may be
missing on this machine; installing them is row 1 of the checklist.

`<home>` is the owner's home folder: `%USERPROFILE%` on Windows,
`$HOME` on macOS. Everything below runs from `<home>/.vimigo/setup`.

Do not fetch anything under `optional/` yet. Those are fetched only if someone
asks for them, which is what keeps a risky one off a machine nobody asked.

## 1. Make sure Node is here

    node --version

If that fails, Node is not installed — and everything below is a Node program.
Read `steps/01-runtimes/README.md` and the platform file beside it, which you
have just downloaded, and install Node now.

That is row 1 of the checklist anyway, so you are not doing extra work, you are
doing it first. Come back here once `node --version` answers. Do not mark the
row done yet — the row needs Git and Python too, and it needs its check to have
run.

## 2. Check the manifest

    node lib/manifest.js https://raw.githubusercontent.com/tengkusyafiq/vimigo-company-os-setup/main/setup/manifest.json

- `"action": "halt"` — stop. Say the `notice` to the owner in your own plain
  words and do nothing else. Do not explain what a manifest is.
- `"action": "refetch"` — do step 0 again, overwriting what is there, then
  carry on.
- `"action": "proceed"` — continue.
- `"offline": true` — continue anyway, and say nothing about it.

## 3. Read or create the state

Use the `version` that step 2 printed:

    node lib/state.js init --version <version from step 2>

This is the checklist, and it lives on disk in `state.json` because this
computer is going to restart before you are finished.

If it prints `"reason":"sandbox"` instead of a checklist, you are not on
their computer. Stop everything, and reply only with the sentence at the very
top of this file.

Recording the version is what lets a later session notice it is running old
instructions and fetch new ones by itself. Leave it out and this machine keeps
whatever it downloaded today, forever.

## 4. Install the master skill

Copy `MASTER.md` to **both**
`<home>/.claude/skills/vimigo-ai-setup/SKILL.md` and
`<home>/.agents/skills/vimigo-ai-setup/SKILL.md`, creating the folders. This is
what lets the owner come back after a restart by saying *"continue my vimigo ai
setup"* instead of pasting anything again, whichever app they open.

If `<home>/.codex/skills/vimigo-ai-setup/` exists, delete it. Codex reads both
`~/.agents/skills` and `~/.codex/skills` — a copy in both places shows up
twice in its skill list.

**Overwrite it if it is already there.** An installed copy is from a previous
run, and every later session reads that copy rather than this file — so a stale
one keeps its fault forever, and the owner has no way to know.

## 5. Finish session 1 first, if it was skipped

    node lib/session1.js

Keep its answer: steps 6 to 8 need its `"joinSync"`, `"declined"` and
`"opensAt"`.

Never decide this from the sync row's own liveness check — that only proves
the last two-minute job ran recently, and reads a perfectly healthy but quiet
laptop (lunch break, bad wifi) as unfinished. This is the check that keeps a
healthy laptop's wrap-up quick.

- **`"handoff": false`** — Say nothing about this check, and go straight to
  step 7.
- **`"handoff": true`** — `runtimes` or `second-brain` isn't done, or
  (`"joinSync": true`) a Vimigo event is open right now and this laptop has
  never joined or said no to any event: session 1 never ran here, or it
  couldn't reach Vimigo. Fetch the local `START.md` and follow it from
  **§5 through §7**, completely and exactly as written — its own
  short-circuit, its "ask who they are" question, and its `sync` row
  included. **Only `START.md`'s own text ever enrols a
  laptop.** However it finishes — including its own short-circuit, which just
  means session 1 turns out to already be done — come back here, to step 6.

  **If `"joinedBefore": true`**, this laptop has already taken part in an
  event, and the hand-off is only for a red setup row: follow `START.md`'s
  §5 and §6, then its `runtimes` and `second-brain` rows only. Skip its
  `sync` row entirely — do not open `steps/03-sync`, do not mention
  saving to Vimigo, and never enrol it into the event open now.
  That is the case even when `START.md` §5's own check says an event
  is open.

A laptop that has already taken part in an event — joined one, or said no to
one — is never handed off for saving to Vimigo from here, whatever event is
open now: it finishes with the event it belongs to. When no event is open,
or Vimigo can't be reached, `"handoff"` is `false` for that too, and step 9
says the right thing.

## 6. Tell them, once

If step 5 said `"declined": true`, or they said no to saving during step 5's
hand-off, go straight to step 9: nothing here is sent, so there is nothing
to write up for Vimigo.

Otherwise say this one line, then go quiet and work through steps 7 and 8:

> *"Give me a few minutes — I'm writing up what you built this week."*

Say it once. Step 8's README has the same line for when it is used on its
own — you have already said it, so do not say it again there.

## 7. Write up their week — only when session 1 never ran

Only when step 5's `"joinSync"` was `true`. Otherwise go straight to step 8.

List their conversations on this computer since the event opened, with the
`"opensAt"` from step 5:

    node lib/sources.js list --since "<opensAt from step 5>"

It lists their Claude Code, Codex and Cowork conversation files changed since
then, oldest first, each with its `path`. Files over 50 MB are already left
out. If it lists nothing, go to step 8.

Read them, oldest first. **Stop reading after about 15 minutes**, even if
some are left, and write up what you have.

Then write in their Second Brain (`<home>/Second Brain`), laid out the way
the second-brain skill lays it out:

- `About me.md` — add what you learned about them and their business: what
  they want AI to help with, how they like to work. Keep their name, company
  and role exactly as they are.
- `Projects/<project>.md` — one page per project: the goal, where it stands,
  the next step.
- `Ideas/<short name>.md` — one per idea worth keeping.
- `Decisions/<YYYY-MM-DD> <short name>.md` — what they decided, and why.
- `Learnings/<short name>.md` — where they got stuck, and what worked.
- `Daily/<YYYY-MM-DD>.md` — one page for each day they actually worked, a
  few lines each.

- Short, plain notes they could read themselves. Write what it meant, never
  a copy of the conversation.
- If a page for the same thing is already there, add to it. Never delete or
  rewrite what is there, and never start a second page for the same thing.
- **Never** write a password, a key, a token, or anything starting `zo_sk_`
  — leave it out entirely, even in passing.

Say nothing while you work, and do not show them the notes unless they ask.
Then go to step 8.

## 8. Write their AI Workflow Submission

Skipped only when step 6 sent you straight to step 9 (`"declined": true`,
or they said no to saving). Otherwise read `steps/05-submission/README.md`,
and the `windows.md` or `macos.md` beside it, and follow it completely: the
submission document in their Second Brain, then the files that show their
work.

Keep to about **10 minutes** for this step. If it runs long, stop and go to
step 9 anyway — the send takes whatever is written by then. The final send
is never held up for the write-up. That README's one question about Google
files is the only thing this step may ask them; time spent waiting for their
answer does not count toward the 10 minutes. After their answer, finish that
README, then go to step 9.

## 9. Send the last of it, and say one line

    node "<home>/.vimigo/setup/lib/sync.js" --final --finish

`<home>` is `%USERPROFILE%` on Windows, `$HOME` on a Mac.

It answers with one `"outcome"`. Choose the line from `"outcome"` alone —
never from `"ok"` or `"reason"` — and say only that line.

If the command stops without printing an answer — it timed out, or was
stopped — treat that exactly as `"outcome": "busy-retry"` below. Never guess
another outcome, and never run anything else instead.

- `"outcome": "sent"` → *"All done. Your work is with Vimigo, and your Second Brain stays on your computer."*
- `"outcome": "declined"` → *"All done. Your Second Brain stays on your computer."*
- `"outcome": "closed"` → *"All done. Your Second Brain stays on your computer."*
- `"outcome": "not-enrolled"` → *"There's nothing to send from this computer — you're all done."*
- `"outcome": "busy-retry"` → Vimigo is busy receiving everyone's work, this
  laptop's own background send was still running, or there is more to send
  than fits in one run (each run stops itself after a few seconds, and the
  next carries on). Say nothing; run the same command again, up to ten more
  times. If it is still `"busy-retry"` after that, say:
  *"Vimigo is busy receiving everyone's work. The rest will send by itself in a few minutes. Your Second Brain stays on your computer."*
  If a try gives another outcome, say that outcome's line instead.
- `"outcome": "offline"` → run the same command once more first; it is
  usually the wifi. If the outcome is still `"offline"`, say:
  *"This computer couldn't reach Vimigo just now. The rest will send by itself when the internet is back. Your Second Brain stays on your computer."*
  If the second try gives another outcome, say that outcome's line instead.
  Do not run `--stop` or anything else: this laptop keeps trying by itself
  and switches itself off when the event closes.
- `"outcome": "nothing-sent"` → run the same command once more first. If it
  is still `"nothing-sent"`, say:
  *"This computer couldn't reach Vimigo, so nothing was sent. Your Second Brain stays on your computer."*
  If the second try gives another outcome, say that outcome's line instead.

That line is the end. Nothing else changes. Their Second Brain, their skills
and their Zo stay exactly as they are.

## Never

- **Never offer Zo here, or start it.** It is too late on the last day; they
  can connect it any time later with the session 2 message.
- **Never enrol by this file's own instructions.** The only file that ever
  enrols a laptop is `START.md`, through its `steps/03-sync` row.
