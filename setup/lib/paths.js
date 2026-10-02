'use strict';
const os = require('node:os');
const path = require('node:path');
const fake = () => !!process.env.VIMIGO_FAKE_HOME;
const home = () => process.env.VIMIGO_FAKE_HOME || os.homedir();
const vimigo = () => process.env.VIMIGO_HOME || path.join(home(), '.vimigo');
// In the home folder itself: macOS guards Documents/Desktop/Downloads from
// background programs, and Windows often redirects Documents into OneDrive.
const brain = () => path.join(home(), 'Second Brain');
const setupDir = () => path.join(vimigo(), 'setup');
// %APPDATA% / %LOCALAPPDATA%. With VIMIGO_FAKE_HOME set, these are ALWAYS the
// fake home's own AppData, whatever the environment says - a test or a hand
// run that set only the fake home must never read the real Claude folders.
// macOS paths already go through home().
const appData = () => (fake() ? null : process.env.APPDATA) || path.join(home(), 'AppData', 'Roaming');
const localAppData = () => (fake() ? null : process.env.LOCALAPPDATA) || path.join(home(), 'AppData', 'Local');
// Claude Desktop's own folder (its config, and Cowork's session files).
const claudeApp = () => (process.platform === 'darwin'
  ? path.join(home(), 'Library', 'Application Support', 'Claude')
  : path.join(appData(), 'Claude'));
// Participants' computers are only Windows or macOS. `linux` here means these
// commands are executing inside a sandbox (Claude Cowork, a container) - not
// on the laptop this setup is meant to change. VIMIGO_TEST_PLATFORM lets a
// test simulate that on any host OS, without needing an actual Linux runner;
// VIMIGO_ALLOW_LINUX is the one override past the refusal, and it exists only
// so this suite's own tests keep passing on a Linux CI runner - nothing else
// should ever set either one.
const platform = () => process.env.VIMIGO_TEST_PLATFORM || process.platform;
const isSandboxed = () => platform() === 'linux' && !process.env.VIMIGO_ALLOW_LINUX;
module.exports = { home, vimigo, brain, setupDir, appData, localAppData, claudeApp, isSandboxed, platform };
