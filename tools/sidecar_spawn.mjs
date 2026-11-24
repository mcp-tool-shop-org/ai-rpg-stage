#!/usr/bin/env node
// sidecar_spawn.mjs — spawn the engine sidecar, tee stderr to a log file cleanly.
//
// Godot's subprocess pipe wrappers can hang (godot#102340), so the headless test harness
// starts this small shim via OS.create_process and reads `stderr_file` directly.

import { spawn } from 'node:child_process';
import * as fs from 'node:fs';

const [, , stderrFile, forwardFlag, binPath, ...sidecarArgs] = process.argv;
if (!stderrFile || !binPath) {
  process.exit(2);
}

fs.writeFileSync(stderrFile, '', 'utf-8');
const forward = forwardFlag === '1';

const child = spawn(process.execPath, [binPath, ...sidecarArgs], {
  stdio: ['ignore', 'ignore', 'pipe'],
});

child.stderr.on('data', (chunk) => {
  fs.appendFileSync(stderrFile, chunk);
  if (forward) {
    process.stderr.write(chunk);
  }
});

const stopChild = () => {
  if (!child.killed) {
    child.kill();
  }
};

process.on('SIGTERM', stopChild);
process.on('SIGINT', stopChild);

child.on('error', (err) => {
  fs.appendFileSync(stderrFile, `[sidecar_spawn] ${err.message}\n`);
  process.exit(1);
});

child.on('exit', (code, signal) => {
  process.exit(code ?? (signal ? 1 : 0));
});
