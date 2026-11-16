Please set up my computer for AI. Everything stays on this computer. Reply in one short, plain sentence at a time and don't explain what you are doing. If a step fails, fix it yourself and carry on; never tell me to ask anyone.

1. You must run commands on my own Windows or Mac computer. If you can't (Claude chat, Cowork or a cloud session), tell me to open the Claude app, click Code, start a new Local session (or open the Codex app) and paste this again. If you can run commands but this session is read-only, or blocks writing files or the internet, tell me to give you full access (in Claude Code, switch the mode at the bottom to Bypass permissions; in the Codex app, choose Full access), and carry on once I have.
2. Install Node.js, Git and Python if they are missing (check with node --version, git --version, python --version). On Windows use winget (OpenJS.NodeJS.LTS, Git.Git, Python.Python.3.13, with --silent --accept-package-agreements --accept-source-agreements) and warn me a blue permission box may appear and I should click Yes. On a Mac use Homebrew (brew install node git python@3.13) and warn me it will ask for my Mac password.
3. Make a folder called "Second Brain" in my home folder, with a file called "About me.md" inside it. Ask me once for my name, company and role and write them into About me.md.
4. Make a folder called .secrets in my home folder with an empty file .secrets/.env in it. This is where my API keys and tokens will be kept later, outside my Second Brain.
5. Install two skills. Save the text between each pair of dashed lines as SKILL.md in both .claude/skills/<skill name>/ and .agents/skills/<skill name>/ in my home folder, using the skill name written in its first lines (second-brain, then sme-ai-stack). Replace any older copy.

--------
---
name: second-brain
description: Use at the start of every conversation, and whenever this person decides something, starts a project, or learns something worth keeping. Reads and writes their Second Brain folder so you remember them between conversations.
---
Their Second Brain is the "Second Brain" folder in their home folder, plain markdown, kept on this computer. At the start of every conversation read "About me.md". As you work, save what matters: ideas, decisions, projects and learnings as short notes in Ideas, Decisions, Projects and Learnings folders (make a folder the first time you need it). Never write passwords or keys into it.
--------

--------
---
name: sme-ai-stack
description: Use when this person wants to automate their business, delegate work to AI, connect a tool (WhatsApp, Notion, Google, email, marketing, hosting), store a key or password, or asks what to use. It holds the recommended AI stack for a small business and how to work with this owner.
---
How to work with this owner
- Do things yourself. Do not hand the owner homework or ask them to run steps. Ask only for what only they can give: a login, a code on their phone, or a click on a screen you cannot reach.
- Some software, often Malaysian or Asian, has no official MCP or API. Look on GitHub for one first. If there is none, use computer control or the browser to do the task for them (see Control below). api-anything (https://github.com/goodnight000/api-anything) can turn a website that only has a screen into operations you can call.
- Use a lighter, cheaper model for simple work and the stronger one only for hard thinking, when the app lets you. This saves tokens without losing quality.
- Install a tool only when the owner needs that capability. Most of them need an account, a subscription or a key first.

Start with an interview
When the owner is not sure what to automate, interview them like a consultant before building anything: what the business sells, what they do every day, what repeats, what is slow or goes wrong, and which tools and subscriptions they already use. Then recommend what to build from the stack below and save the result as a short note in the Second Brain. A live voice chat in ChatGPT is a good way for them to talk it through.

The stack
AI
- The coding app is the builder and the runner: Claude Code (the Code tab in the Claude app) or the Codex app (ChatGPT). Either one is enough on its own unless they need jobs that run 24/7 (automations, AI employees), which need hosting. Treat both apps the same: skills go in .claude/skills and .agents/skills, and to add an MCP use claude mcp add for Claude Code, and codex mcp add (or a [mcp_servers.name] section in .codex/config.toml) for Codex.
- Claude Cowork can record the owner's screen while they explain their day. Turn the recording into a markdown skill file and pass it to a coding session. Without Cowork (for example a ChatGPT user), have the owner record their screen with any screen recorder, or just talk through the steps in a ChatGPT voice chat, then turn the recording or transcript into a markdown skill file the same way.
- Cheaper model APIs (DeepSeek, OpenAI luna max) lower the cost of high-volume automations.
- Marketing: Higgsfield (video generation) and ElevenLabs (voice), each connected to Claude Code or Codex. The fastest way to a good result is a reference: the owner gives a viral video, ad or page and asks you to reverse-engineer it into a reusable marketing skill for their company. Editing raw video: just use Claude. Generating video or voice needs Higgsfield and ElevenLabs subscriptions and their MCPs.
Tools (MCP)
- WhatsApp: the hosted WhatsApp MCP at https://wamcp.vimigo.io, an unofficial MCP with more capabilities than the official ones. Never promise that a number cannot be blocked.
- Notion (free plan): make one integration key and let every employee and AI use it through their AI app. People get read-only access, unless several must edit, which needs a paid plan.
- Google: the Calendar, Drive, Sheets and Docs MCPs.
- Email: for a company that runs its own mail server (for example Roundcube), use the email MCP at https://github.com/codefuturist/email-mcp
- Web and social research: agent-reach (https://github.com/Panniantong/agent-reach).
Control
- Claude users: Claude desktop's computer control (the laptop) and Claude for Chrome (the browser).
- ChatGPT users: the matching features of the ChatGPT and Codex apps, such as ChatGPT's agent mode for the browser. Check what the owner's app offers today before promising anything; if it has no such feature, say so plainly and use another route.
Hosting
- Zo Computer is the easy option.
- Or Coolify on Hostinger, to host an AI chat agent, automations (for example Hermes), a Postgres database and files.
- Domain names: Hostinger or Cloudflare.

Keys and passwords
- Keep every API key and token in one file, .secrets/.env in the home folder, never inside the Second Brain and never in notes or shared code.
- To get a key from the owner, ask them to copy it (Ctrl+C, or Cmd+C on a Mac) and say when done. Then read it from the clipboard yourself (Get-Clipboard on Windows, pbpaste on a Mac), save it into that file, tell them only "saved, N characters", and clear the clipboard. Never ask them to open the file or paste it into it themselves.
- If they paste a key into the chat anyway, save it the same way and do not repeat it back.
- Bank and personal login passwords do not go in that file.
--------

6. Add the block between the two marker lines to .claude/CLAUDE.md and .codex/AGENTS.md in my home folder. Create the files if missing and keep what is already there. If the marker lines are already there, replace what is between them instead of adding a second block.

<!-- ai-setup:start -->
This person keeps a Second Brain in the "Second Brain" folder in their home folder. At the start of each conversation use the second-brain skill. For anything about automating work, connecting tools, marketing, hosting or keys, use the sme-ai-stack skill. Do things yourself instead of asking the owner to; ask only for what only they can give. Use a lighter, cheaper model for simple work when you can, and keep the stronger one for hard thinking, so tokens are saved without losing quality.
<!-- ai-setup:end -->

7. When it is all done, say only: "All done."
