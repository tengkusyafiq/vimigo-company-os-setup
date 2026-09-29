'use strict';
// Anything shaped like a secret is replaced before it leaves the laptop. A
// backstop to the skill's own rule: session 2 has the owner paste their Zo key
// into the chat, and that chat is synced.
const Q = `(?:\\\\?["'])?`;                       // optional quote, optionally JSON-escaped
const NAMES = '(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)';
// One "value character": not whitespace, quote, apostrophe, comma, semicolon,
// brace or backslash - the same exclusions as before - plus "|", so a run
// stops cleanly at a markdown table cell or a CSV field without being told
// which layout it is in.
const XVAL = `[^\\s"',;}{\\\\|]`;
// An unquoted value only counts as secret-shaped if it runs 8+ characters with
// no delimiter inside it AND carries a digit or one of _-/+= - what tells
// "hunter22" or "A1b2C3d4E5f6G7h8xyz" apart from an ordinary sentence word
// ("keep", "expected"). Quoted values keep no such test: deliberately quoting
// a value next to a secret-shaped name is itself the signal.
const UNQUOTED = `(?=${XVAL}{8,})(?=${XVAL}*[0-9_\\-\\/+=])${XVAL}+`;
// Delimiter between a secret-shaped name and its value: ":" or "=" as before,
// plus "|" (a markdown table cell) and "," (a CSV row), all optionally padded
// with spaces.
const SEP = '\\s*[:=|,]\\s*';
const GENERIC = new RegExp(
  `(?<prefix>${Q}${NAMES}${Q}${SEP})` +
  `(?:\\\\"(?<esc>(?:[^"\\\\\\n]|\\\\[^"])*)\\\\"` +
  `|"(?<dq>[^"\\n]*)"` +
  `|'(?<sq>[^'\\n]*)'` +
  `|(?<unq>${UNQUOTED}))`,
  'gi'
);
// The value's own quote style (plain quote, apostrophe, or JSON-escaped
// quote) travels into the replacement instead of a hard-coded one, so
// {\"api_key\": \"abcd1234efgh\"} comes back {\"api_key\": \"[redacted]\"}
// rather than a mismatched, still-parseable-looking {\"api_key\": "[redacted]"}.
function redactGeneric(match, ...rest) {
  const groups = rest[rest.length - 1];
  const { prefix, esc, dq, sq } = groups;
  if (esc !== undefined) return prefix + '\\"[redacted]\\"';
  if (dq !== undefined) return prefix + '"[redacted]"';
  if (sq !== undefined) return prefix + "'[redacted]'";
  return prefix + '[redacted]';
}
const RULES = [
  // A wrapped zo_sk_ key (a real line break, or the two-character \n a
  // JSON-stringified chat log leaves behind) still has its tail redacted -
  // repeated, so more than one wrap in a row is still fully covered.
  [/zo_sk_[A-Za-z0-9_\-]{8,}(?:(?:\r\n|\\r\\n|\n|\\n)[A-Za-z0-9_\-]{4,})*/g, 'zo_sk_[redacted]'],
  [/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----/g, '[redacted private key]'],
  [/\bsk-(?:ant-|proj-)?[A-Za-z0-9_\-]{20,}/g, 'sk-[redacted]'],
  [/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}/g, '[redacted token]'],
  [/\bgithub_pat_[A-Za-z0-9_]{20,}/g, '[redacted token]'],
  [/\bAKIA[0-9A-Z]{16}\b/g, '[redacted key]'],
  [/\bxox[abprs]-[A-Za-z0-9\-]{10,}/g, '[redacted token]'],
  [/\bAIza[0-9A-Za-z_\-]{35}\b/g, '[redacted key]'],
  // Case-insensitive: a header reading "authorization: bearer ..." is as real
  // as "Authorization: Bearer ...". $1 carries the actually-matched casing
  // through unchanged, so the word itself is never rewritten.
  [/\b(Bearer)\s+[A-Za-z0-9._~+\/\-]{20,}=*/gi, '$1 [redacted]'],
  [GENERIC, redactGeneric],
];
function scrubText(s) { let out = String(s); for (const [re, rep] of RULES) out = out.replace(re, rep); return out; }
function isText(buf) { const n = Math.min(buf.length, 8192); for (let i = 0; i < n; i++) if (buf[i] === 0) return false; return true; }
function scrubBuffer(buf) {
  if (!isText(buf)) return buf;
  const s = buf.toString('utf8'); const out = scrubText(s);
  return out === s ? buf : Buffer.from(out, 'utf8');
}
module.exports = { scrubText, scrubBuffer, isText };
