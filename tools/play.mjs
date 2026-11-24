#!/usr/bin/env node
// play.mjs — start the sim and open the stage. One command.
//
//   node tools/play.mjs
//
// This exists because "Mike plays it" is C4's actual exit gate, and a two-terminal dance
// with a port to remember is a reason not to. It starts the sidecar with Salt Road loaded,
// waits until the port is genuinely accepting connections, launches Godot pointed at it,
// and shuts the sim down when the window closes.
//
// Node is used for the launcher and nothing else — the client itself has no JavaScript in
// it and needs none. This file is a process babysitter.
//
// Options:
//   --seed <n>          session seed (default 71 — the seed every proof in this repo uses)
//   --port <n>          sidecar port (default 47820)
//   --shock <spec>      scenario cue, <district>:<metric>:<delta>@<round>
//                       (default dockward:stability:-25@2 — the quay turns on round 2)
//   --no-shock          run with no cue at all
//   --engine <dir>      engine checkout (default ../ai-rpg-engine)
//   --forge <dir>       world-forge checkout (default ../world-forge)
//   --unresolved-ai-profile <fail|warn>  policy for unresolved entity profiles (default: fail)
//   --release                            shorthand for --unresolved-ai-profile warn
//   --headless                           start the sim only, print the port, and wait. For attaching the
//                                        editor, or for driving it by hand.

import { spawn } from 'node:child_process';
import * as net from 'node:net';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STAGE = path.resolve(HERE, '..');

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const prefix = `--${name}=`;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i].startsWith(prefix)) return argv[i].slice(prefix.length);
    if (argv[i] === `--${name}` && argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')) {
      return argv[i + 1];
    }
  }
  return fallback;
};
const has = (name) => argv.includes(`--${name}`);

const SEED = flag('seed', '71');
const PORT = Number(flag('port', '47820'));
const ENGINE = path.resolve(flag('engine', path.join(STAGE, '..', 'ai-rpg-engine')));
const FORGE = path.resolve(flag('forge', path.join(STAGE, '..', 'world-forge')));
const SHOCK = has('no-shock') ? null : flag('shock', 'dockward:stability:-25@2');
const PROFILE_MODE = flag('unresolved-ai-profile', has('release') ? 'warn' : 'fail');
const HOST_PACK = 'chapel-threshold';

const BIN = path.join(ENGINE, 'packages', 'cli', 'dist', 'bin.js');
const PACK = path.join(FORGE, 'dogfood', 'output', 'salt-road', 'pack.json');
const MANIFEST = path.join(STAGE, 'fixtures', 'salt-road.manifest.json');

function die(message, hint) {
  console.error(`\n✗ ${message}`);
  if (hint) console.error(`  ${hint}`);
  process.exit(1);
}

if (PROFILE_MODE !== 'fail' && PROFILE_MODE !== 'warn') {
  die(
    `invalid --unresolved-ai-profile "${PROFILE_MODE}"`,
    'Expected fail or warn.',
  );
}

// --- Preconditions, each with the command that fixes it ---------------------
// A launcher that fails with a stack trace is a launcher nobody uses twice.

if (!fs.existsSync(BIN)) {
  die(
    `the engine CLI is not built at ${BIN}`,
    `cd "${ENGINE}" && npm ci && npm run build   (or pass --engine <dir>)`,
  );
}
if (!fs.existsSync(PACK)) {
  die(
    `Salt Road has not been exported to ${PACK}`,
    `cd "${FORGE}" && npx tsx dogfood/export-stage-fixture.ts --world=salt-road `
      + `--out="${path.join(STAGE, 'fixtures')}" --doctor   (or pass --forge <dir>)`,
  );
}
if (PROFILE_MODE !== 'fail' && PROFILE_MODE !== 'warn') {
  die(
    `invalid --unresolved-ai-profile "${PROFILE_MODE}"`,
    'Expected fail or warn.',
  );
}
if (!fs.existsSync(MANIFEST)) {
  die(
    `Salt Road manifest missing at ${MANIFEST}`,
    `the sidecar load gate requires --manifest beside --content`,
  );
}

// --- The sim ----------------------------------------------------------------

const simArgs = [
  BIN, 'sidecar', HOST_PACK,
  '--seed', SEED,
  '--content', PACK,
  '--manifest', MANIFEST,
  '--start', 'counting-house',
  '--unresolved-ai-profile', PROFILE_MODE,
  '--listen', String(PORT),
  ...(SHOCK ? ['--shock', SHOCK] : []),
];

const STDERR_LOG = path.join(os.tmpdir(), `ai-rpg-stage-sidecar-${process.pid}.stderr.log`);
fs.writeFileSync(STDERR_LOG, '', 'utf-8');
const cleanupStderrLog = () => {
  try { fs.unlinkSync(STDERR_LOG); } catch {}
};

console.log('── Salt Road: The Long Quay ──');
console.log(`sim    node ${simArgs.slice(1).join(' ')}`);

const sim = spawn(process.execPath, simArgs, { stdio: ['ignore', 'ignore', 'pipe'] });

let simLog = '';
sim.stderr.on('data', (chunk) => {
  const text = chunk.toString('utf-8');
  simLog += text;
  fs.appendFileSync(STDERR_LOG, text, 'utf-8');
  // The sim's own diagnostics, forwarded. `dropped` and `warning` lines especially:
  // what the load gate did NOT carry or warned about must surface cleanly.
  for (const line of text.split('\n')) {
    if (line.trim()) console.log(`       ${line.trim()}`);
  }
});

sim.on('exit', (code) => {
  if (code !== null && code !== 0) {
    cleanupStderrLog();
    die(`the sim exited ${code} before the stage could attach`, simLog.trim() || undefined);
  }
});

/** Wait until the port genuinely accepts a connection, not merely until the child spawned. */
async function waitForPort(port, timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ok = await new Promise((resolve) => {
      const s = net.createConnection({ port, host: '127.0.0.1' }, () => {
        s.destroy();
        resolve(true);
      });
      s.on('error', () => resolve(false));
    });
    if (ok) return true;
    await new Promise((r) => setTimeout(r, 150));
  }
  return false;
}

const up = await waitForPort(PORT);
if (!up) {
  sim.kill();
  cleanupStderrLog();
  die(`the sim never accepted a connection on 127.0.0.1:${PORT}`, simLog.trim() || undefined);
}
console.log(`sim    ready on 127.0.0.1:${PORT}`);

// Give the sidecar a moment to release the slot the probe above just used — it serves ONE
// client at a time, deliberately, and the probe was that client.
await new Promise((r) => setTimeout(r, 250));

if (has('headless')) {
  console.log('\nsim is up. Attach a client to 127.0.0.1:%d — ctrl-c to stop.', PORT);
  process.on('SIGINT', () => {
    sim.kill();
    cleanupStderrLog();
    process.exit(0);
  });
  await new Promise(() => {});
}

// --- The stage --------------------------------------------------------------

const godot = process.env.GODOT_BIN || 'godot';
console.log(`stage  ${godot} --path . (attaching to ${PORT})`);

const view = spawn(
  godot,
  ['--path', STAGE, '--', `--attach=127.0.0.1:${PORT}`, `--sidecar-stderr=${STDERR_LOG}`],
  {
    stdio: 'inherit',
    cwd: STAGE,
  },
);

view.on('error', (err) => {
  sim.kill();
  cleanupStderrLog();
  die(
    `could not launch Godot (${err.message})`,
    'Install Godot 4.7.x on PATH, or set GODOT_BIN to its executable.',
  );
});

// The sim outlives nothing. When the window closes, the world closes with it — a stray
// sidecar holding a port is the thing that makes the next run fail confusingly.
view.on('exit', (code) => {
  sim.kill();
  cleanupStderrLog();
  process.exit(code ?? 0);
});

process.on('SIGINT', () => {
  view.kill();
  sim.kill();
  cleanupStderrLog();
  process.exit(0);
});
