#!/usr/bin/env node
'use strict';
// The server address, kept out of plain sight so a scraper grepping public
// GitHub for URLs does not find an upload door. A speed bump, not security:
// the door itself cannot read, list or overwrite anybody's files.
const rev = (s) => [...s].reverse().join('');
function encode(url) { return Buffer.from(rev(String(url).replace(/\/+$/, '')), 'utf8').toString('base64'); }
function decode(e) {
  const url = rev(Buffer.from(String(e || ''), 'base64').toString('utf8')).replace(/\/+$/, '');
  if (!/^(https:\/\/[A-Za-z0-9.-]+(:\d+)?|http:\/\/(127\.0\.0\.1|localhost)(:\d+)?)(\/[^\s]*)?$/.test(url)) {
    throw new Error('not a usable address');
  }
  return url;
}
if (require.main === module) {
  const [cmd, arg] = process.argv.slice(2);
  if (cmd === 'encode' && arg) process.stdout.write(encode(arg) + '\n');
  else if (cmd === 'decode' && arg) process.stdout.write(decode(arg) + '\n');
  else { process.stderr.write('usage: endpoint.js encode|decode <value>\n'); process.exit(2); }
}
module.exports = { encode, decode };
