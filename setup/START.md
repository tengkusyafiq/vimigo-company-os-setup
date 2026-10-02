Please set up my computer for AI. Everything stays on this computer. Reply in one short, plain sentence at a time and don't explain what you are doing.

1. You must run commands on my own Windows or Mac computer. If you can't (Claude chat, Cowork or a cloud session), tell me to open the Claude app, click Code, start a new Local session (or open the Codex app) and paste this again.
2. Install Node.js, Git and Python if they are missing (check with node --version, git --version, python --version). On Windows use winget (OpenJS.NodeJS.LTS, Git.Git, Python.Python.3.13, with --silent --accept-package-agreements --accept-source-agreements) and warn me a blue permission box may appear and I should click Yes. On a Mac use Homebrew (brew install node git python@3.13) and warn me it will ask for my Mac password.
3. Make a folder called "Second Brain" in my home folder, and inside it a folder called "Daily" and a file called "About me.md". Ask me once for my name, company and role and write them into About me.md.
4. Install the Second Brain skill: save the text between the two lines of dashes as SKILL.md in both .claude/skills/second-brain/ and .agents/skills/second-brain/ in my home folder.

--------
---
name: second-brain
description: Use at the start of every conversation, and whenever this person decides something, starts a project, or learns something worth keeping. Reads and writes their Second Brain folder so you remember them between conversations.
---
Their Second Brain is the "Second Brain" folder in their home folder, plain markdown, kept on this computer. At the start of every conversation read "About me.md" and today's page in Daily (create it if missing). As you work, save what matters: ideas, decisions, projects and learnings as short notes in Ideas, Decisions, Projects and Learnings folders, and one or two lines about what you did in Daily/<today>.md after each reply where you did real work. Never write passwords or keys into it.
--------

5. Add this line to .claude/CLAUDE.md and .codex/AGENTS.md in my home folder (create the files if missing, keep what is already there): This person keeps a Second Brain in the "Second Brain" folder in their home folder. At the start of each conversation use the second-brain skill.
6. When it is all done, say only: "All done."
