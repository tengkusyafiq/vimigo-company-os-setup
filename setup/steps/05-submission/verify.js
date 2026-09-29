#!/usr/bin/env node
'use strict';
// The wrap-up's submission (steps/05-submission/README.md). Read-only: it
// names the one document to write, and checks it and Submission/files/.
//
//   node steps/05-submission/verify.js
//
// { ok, evidence, company, file, missing: [section], remove: [path] }
//   company  exactly as About me.md has it (null when it has none yet)
//   file     <home>/Second Brain/Submission/<Company> – AI Workflow Submission.md
//            (characters a file name cannot hold become "-"; the title keeps them)
//   missing  the fifteen sections the document does not have yet
//   remove   anything in Submission/files/ that must never be sent, or is over 50 MB
// Not a checklist row: it writes no receipt.
const fs = require('node:fs');
const path = require('node:path');
const { brain } = require('../../lib/paths.js');
const { SKIP_DIRS, SKIP_FILE } = require('../../lib/sources.js');

const SECTIONS = ['Executive Summary', 'Participant Information', 'Company Background', 'Business Problem',
  'Previous Workflow', 'AI Workflow Built', 'Step-by-Step Workflow', 'Tools and AI Features Used',
  'Deliverables Created', 'Before-and-After Comparison', 'Results and Business Impact', 'Current Project Status',
  'Challenges and Unresolved Issues', 'Recommended Next Steps', 'Supporting Files'];
const MAX = 50 * 1024 * 1024;
// Folders that are never a deliverable: git history, dependencies, caches.
const NEVER_DIR = new Set([...SKIP_DIRS, '.svn', '.hg', '.idea', 'dist-cache']);

function company() {
  let text; try { text = fs.readFileSync(path.join(brain(), 'About me.md'), 'utf8'); } catch { return null; }
  const m = text.match(/^\s*[-*]\s*\*\*Company:\*\*[ \t]*(.*)$/m);
  const c = m ? m[1].trim() : '';
  return c || null;
}
// Windows cannot hold \ / : * ? " < > | in a file name. (A company's own
// trailing dot, "Sdn. Bhd.", is fine: the name goes on after it.)
const safe = (c) => c.replace(/[\\/:*?"<>|\x00-\x1f]/g, '-').trim();

function problems(dir) {
  const out = [];
  const visit = (d) => {
    let entries; try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const abs = path.join(d, e.name);
      if (e.isSymbolicLink()) { out.push(abs); continue; }
      if (e.isDirectory()) { if (NEVER_DIR.has(e.name)) out.push(abs); else visit(abs); continue; }
      if (SKIP_FILE.some((re) => re.test(e.name))) { out.push(abs); continue; }
      try { if (fs.statSync(abs).size > MAX) out.push(abs); } catch { /* gone */ }
    }
  };
  visit(dir);
  return out;
}

function check() {
  const c = company();
  const root = path.join(brain(), 'Submission');
  const remove = problems(path.join(root, 'files'));
  if (!c) return { ok: false, evidence: 'no company name yet', company: null, file: null, missing: SECTIONS, remove };
  const file = path.join(root, `${safe(c)} – AI Workflow Submission.md`);
  let doc = null; try { doc = fs.readFileSync(file, 'utf8'); } catch { /* not yet */ }
  if (doc === null) return { ok: false, evidence: 'not written yet', company: c, file, missing: SECTIONS, remove };
  const headings = (doc.match(/^#{2,3}\s+.*$/gm) || []).map((h) => h.replace(/^#+\s+(\d+\.\s*)?/, '').trim().toLowerCase());
  const missing = SECTIONS.filter((s) => !headings.includes(s.toLowerCase()));
  const diagram = /```mermaid\b/.test(doc);
  if (missing.length || !diagram) {
    return { ok: false, evidence: missing.length ? `${missing.length} sections still to write` : 'no workflow diagram yet',
      company: c, file, missing, diagram, remove };
  }
  if (remove.length) return { ok: false, evidence: 'some files must not be sent', company: c, file, missing, diagram, remove };
  return { ok: true, evidence: 'submission written', company: c, file, missing, diagram, remove };
}

const r = check();
process.stdout.write(JSON.stringify(r) + '\n');
if (!r.ok) process.exitCode = 1;
