'use strict';
// The channel between a verifier and the checklist.
//
// Without this, "evidence" was a string the AI typed, and the rule that a row
// goes green only on evidence it did not generate itself was enforced by
// nothing - `--evidence " "` marked a row done, and two of the three verifiers
// print a fixed literal that is published in the same tree the AI reads.
//
// A verifier writes a receipt when it passes. `state.js set <id> done` refuses
// unless a passing receipt exists AND the evidence matches it exactly. Marking
// a row done now requires having actually run the check.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dir = () =>
  path.join(process.env.VIMIGO_HOME || path.join(os.homedir(), '.vimigo'), 'receipts');

function write(id, payload) {
  fs.mkdirSync(dir(), { recursive: true });
  const tmp = path.join(dir(), id + '.json.tmp');
  fs.writeFileSync(tmp, JSON.stringify({ ...payload, at: new Date().toISOString() }) + '\n');
  fs.renameSync(tmp, path.join(dir(), id + '.json'));
}

function read(id) {
  try {
    const r = JSON.parse(fs.readFileSync(path.join(dir(), id + '.json'), 'utf8'));
    return r && typeof r === 'object' ? r : null;
  } catch {
    return null;
  }
}

// A failing check has to withdraw the last passing one, not merely decline to
// add another. A verifier with a bug wrote a receipt saying Hermes One was
// installed on a machine that had never had it; the bug was fixed within the
// minute, and the receipt sat there afterwards saying the same thing, ready for
// the next `set hermes done`. The expiry would have cleared it half an hour
// later, which is longer than the whole setup takes.
function clear(id) {
  try {
    fs.unlinkSync(path.join(dir(), id + '.json'));
  } catch { /* nothing to withdraw */ }
}

module.exports = { write, read, clear, dir };
