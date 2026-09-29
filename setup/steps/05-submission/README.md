# Step 5 — their AI Workflow Submission (wrap-up only)

Only from `WRAP-UP.md`, right before the final send. This is not a row on the
checklist, and it installs nothing.

You write up what this person built during the Vimigo event, as a business
document, into their own Second Brain, and gather the files that show it.
Their Second Brain goes to Vimigo with the final send, so this is how the
submission reaches Vimigo — nothing is uploaded to their Google Drive, and
nothing is shared with anyone.

Everything below runs from `<home>/.vimigo/setup`. `<home>` is `%USERPROFILE%`
on Windows, `$HOME` on a Mac. The platform file beside this one
(`windows.md` or `macos.md`) says where their files tend to be.

## Tell them once, first

If `WRAP-UP.md` already said this line in this session, it has already said
it — do not say it again. Otherwise say it now, then go quiet and work:

> *"Give me a few minutes — I'm writing up what you built this week."*

## Keep to about 10 minutes

Budget about **10 minutes** for this whole step. Write the document first,
then gather the files. If you run out of time, stop where you are and go
back to `WRAP-UP.md` for the send — never hold up the final send for this:
send what exists. A shorter document that is there beats a perfect one that
is not.

## Which file

    node steps/05-submission/verify.js

It answers with `"company"` (exactly as `About me.md` has it), and `"file"` —
the one document to write:

    Submission/<Company> – AI Workflow Submission.md

inside their Second Brain (`<home>/Second Brain`). Use that `"file"` exactly.
If `"file"` is `null`, `About me.md` has no company yet: use the company name
you already have from this session, written into `About me.md` as
`- **Company:** <name>` exactly as they gave it, then run `verify.js` again.

If that document is already there (wrap-up run twice), read it and update it
in place. Never start a second document, and never put any other `.md` file
directly in `Submission/` — Vimigo's dashboard shows the one there as their
submission.

## The evidence

Work from what is already on this computer. Do not ask them to describe
their work unless you have looked and still cannot tell.

1. **Their Second Brain** — `About me.md`, `Projects/`, `Decisions/`,
   `Learnings/`, `Ideas/`, and the `Daily/` pages from the event days.
2. **Their conversations since the event opened.** Use the `"opensAt"` that
   `WRAP-UP.md` step 5 kept:

       node lib/sources.js list --since "<opensAt>"

   It lists their Claude Code, Codex and Cowork conversation files from then
   on, oldest first (files over 50 MB are already left out). If `WRAP-UP.md`
   step 7 has just read them, use what you learned there instead of reading
   them again. Read the ones about their project, not every one.
3. **The files they made** — `Projects/**/files/`, and any place their notes
   name.

Match on the work, not on folder names. **Do not** read or include unrelated
projects, unrelated conversations, or unrelated personal files: whatever else
is on this laptop is their business and their clients'.

The files they built matter more than the conversation. Working code, a
dashboard, a report and a README are better evidence than a chat about
making them.

## What to work out

**Business background** — what the company does, the industry, the people
involved, the business problem, and why it matters.

**Previous workflow** — how the task was done before, by whom, how many
manual steps, how long it took, the usual delays, mistakes and rework.

**The AI workflow they built** — step by step. For every step: the trigger,
the input, the action, the AI or tool used, the human approval point, the
output, where the data is kept, and what happens next.

**Tools used** — only ones the evidence shows were actually used. Do not list
a tool that was only discussed.

**Deliverables** — the real ones, with their file names.

**Results** — time before and after, time saved, manual steps removed,
errors reduced, faster response, better visibility, likely cost saving,
likely revenue impact, team capacity freed.

**Never invent a number.** Label every result as exactly one of:

- **Verified result** — measured, and the evidence is on this computer
- **Evidence-based estimate** — worked out from something real; say from what
- **Not yet measured**

"Not yet measured" is a perfectly good answer. A made-up figure is worse than
none.

## The document

Title it exactly `<Company> – AI Workflow Submission`, with the company name
exactly as `About me.md` has it — do not correct its spelling. Clear business
English; a line of Chinese explanation is fine where it helps. Write it for
Vimigo's team, not for the owner: no file paths in the prose, no keys, no
passwords, nothing starting `zo_sk_`.

These fifteen sections, in this order, with exactly these headings:

```markdown
# <Company> – AI Workflow Submission

## 1. Executive Summary
## 2. Participant Information
## 3. Company Background
## 4. Business Problem
## 5. Previous Workflow
## 6. AI Workflow Built
## 7. Step-by-Step Workflow
## 8. Tools and AI Features Used
## 9. Deliverables Created
## 10. Before-and-After Comparison
## 11. Results and Business Impact
## 12. Current Project Status
## 13. Challenges and Unresolved Issues
## 14. Recommended Next Steps
## 15. Supporting Files
```

Also include:

- **one Mermaid workflow diagram**, in section 6 or 7, as a fenced block:

      ```mermaid
      flowchart LR
        A[Customer message] --> B[AI drafts a reply] --> C{Owner approves?} --> D[Sent]
      ```

- **one before-versus-after table** in section 10 (step, before, after);
- **one tools-and-purpose table** in section 8 (tool, what it was used for);
- **one results table** in section 11 (result, figure, label — one of the
  three labels above);
- **one supporting-files list** in section 15 (see below).

A section with nothing to say still gets its heading and one honest line
("Not yet measured.", "None found."). Then run `verify.js` again: it names any
section still missing.

## Supporting files

### 1. What they built, on this computer

Make sure the files that matter are inside their Second Brain, under
`Submission/files/`: what they built, reports, screenshots, prompts, sample
input and output, a README or demo instructions. Copy them in from
`Projects/**/files/` and from the places their notes or conversations name.
Keep folder names short and plain. Copy — never move or delete the original.

**Never upload** `.env` files, passwords, API keys, access tokens,
authentication files, cookies, `node_modules`, cache folders, git history,
unrelated company files, unrelated personal files, or customer information
the submission does not need. Where confidential business data appears in a
file worth including, make a redacted copy instead.

Skip any single file over **50 MB** (videos, installers). Name it in the list
instead.

### 2. Google Docs, Slides and Sheets

**If a Google Drive (or Google Workspace) tool is available to you in this
session**, find the files they **created or edited since** the event opened
(`"opensAt"`) that belong to this project. Export each one into
`Submission/files/`: Docs and Slides as **PDF**, Sheets as **XLSX**, named
after the file. Never export anything unrelated to the project, and never
change, move or share anything in their Drive.

**If no such tool is here**, do not ask them to install or connect one, and
do not mention it. List every Google link you find in their notes and
conversations (`docs.google.com`, `drive.google.com`) in section 15, each
marked **not attached — link only**.

### 3. The list

In section 15, list every supporting file: its name, what it shows, and
whether it is essential or optional. Google links that are not attached are
listed there too, marked as above.

Then:

    node steps/05-submission/verify.js

- `"ok": true` — done. Go back to `WRAP-UP.md` for the send.
- `"missing"` names a section — add it.
- `"remove"` lists anything in `Submission/files/` that must never be sent,
  or is over 50 MB — delete exactly those copies from `Submission/files/`
  (never the originals elsewhere), and run it once more.

Say nothing to them about the document, and do not show it unless they ask.
If they ask, show it — it is theirs.
