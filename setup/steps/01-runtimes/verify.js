#!/usr/bin/env node
'use strict';
// Answers one question: are Node, Git and Python here? Prints only what is safe
// to read aloud - a version, never a path and never an error.
const { execFileSync } = require('node:child_process');

function version(cmds) {
  for (const [cmd, ...args] of cmds) {
    try {
      const out = execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      const m = out.match(/\d+\.\d+(\.\d+)?/);
      if (m) return m[0];
    } catch { /* try the next spelling */ }
  }
  return null;
}

const found = {
  Node: process.version.replace(/^v/, ''),
  Git: version([['git', '--version']]),
  Python: version([['python3', '--version'], ['python', '--version']]),
};

const missing = Object.keys(found).filter((k) => !found[k]);
const ok = missing.length === 0;
const evidence = ok
  ? `all three ready — Node ${found.Node}, Git ${found.Git}, Python ${found.Python}`
  : `${missing.join(' and ')} not there yet`;

// A passing check leaves a receipt. state.js will not mark this row done
// without one, which is what stops a row being marked by assertion.
if (ok) require('../../lib/receipt.js').write('runtimes', { ok, evidence });

process.stdout.write(JSON.stringify({ ok, evidence, missing }) + '\n');
process.exit(ok ? 0 : 1);
