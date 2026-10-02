---
name: second-brain
description: Use at the start of every conversation, and whenever this person brainstorms, decides something, starts or finishes a project, gets stuck, or learns something worth keeping. Reads and writes their Second Brain - a folder of plain notes that Claude and ChatGPT share - so you remember them between conversations.
---

# Their Second Brain

A folder called **Second Brain** in their home folder: `%USERPROFILE%\Second Brain`
on Windows, `~/Second Brain` on a Mac. Plain markdown. It is theirs.

`<home>` below is that same home folder: `%USERPROFILE%` on Windows, `$HOME`
on a Mac.

## At the start of every conversation

1. Read `About me.md` and today's page in `Daily/` (create it if missing: a
   heading with today's date).
2. Run the start-up check, quietly:

       node "<home>/.vimigo/setup/lib/doctor.js"

   - `"zo"` shows `false` for the app you are — connect Zo to this app from the
     key already in the other one, following `steps/04-zo/windows.md` or
     `macos.md`, "Registering Zo with both apps". Never ask them for the key
     again.
   - Everything else: say nothing. It repairs itself.

   If that file is not there, skip this step — the setup was never run here.

## As you work — save what matters, without being asked

| When | Where |
|---|---|
| They tell you about their business, what they want AI to help with, or how they like to work | `About me.md` — fill in its sections; keep it short and current |
| They brainstorm, or have an idea | `Ideas/<short name>.md` |
| They decide something, and why | `Decisions/<date> <short name>.md` |
| A project starts or moves on | `Projects/<project>.md` — goal, status, next step |
| They get stuck, or something works | `Learnings/<short name>.md` |
| You did anything for them in this conversation — answered a question about their work, researched, drafted, built, fixed, decided | one or two lines in `Daily/<today>.md`, before you finish that reply: what they asked, and what came out of it |

Copy the files that matter — what they built, reports, screenshots, prompts —
into `Projects/<project>/files/`. Keep the whole folder under about **500 MB**,
and skip any single file over **50 MB** (videos, installers).

Write short, plain notes they could read themselves. Update a page rather than
starting a new one when it is the same thing.

**Never** write a password, a key, a token, or anything starting `zo_sk_`.

The Daily page is the one that should grow every day: a short running log of
what you did together, so tomorrow's conversation — and their end-of-class
write-up — can pick up where today left off. Skip only small talk.

Do not announce each save. A one-word mention is fine if it fits naturally.

## If they ask whether their work goes anywhere

Tell the truth, plainly: it stays on this computer. Nothing is sent anywhere
unless they choose to share it themselves on the last day of the class, by pasting
that day's message. Their AI conversations are never sent.

## More skills

`<home>/.vimigo/setup/SKILLS.md` lists what else Vimigo offers. When they ask
for something one of them does, install it:

    node "<home>/.vimigo/setup/lib/skills.js" install <name>

It is ready the next time the app opens.
