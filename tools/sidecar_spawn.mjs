#!/usr/bin/env node
// sidecar_spawn.mjs — run the engine sidecar in this single process while teeing stderr.
//
// Godot's subprocess pipe wrappers can hang (godot#102340), so the headless test harness
// launches this wrapper via OS.create_process and reads `stderrFile` directly. Running the
// engine CLI in-process ensures OS.kill(pid) terminates the listening socket immediately on
// every platform (no grandchild process left holding a candidate port).

import * as fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const [, , stderrFile, forwardFlag, binPath, ...sidecarArgs] = process.argv;
if (!stderrFile || !binPath) {
  process.exit(2);
}

fs.writeFileSync(stderrFile, '', 'utf-8');
const forward = forwardFlag === '1';
const rawStderrWrite = process.stderr.write.bind(process.stderr);

process.stderr.write = (chunk, encoding, callback) => {
  let cb = callback;
  let enc = encoding;
  if (typeof encoding === 'function') {
    cb = encoding;
    enc = 'utf-8';
  }
  const text = typeof chunk === 'string' ? chunk : chunk.toString(typeof enc === 'string' ? enc : 'utf-8');
  fs.appendFileSync(stderrFile, text, 'utf-8');
  if (forward) {
    return rawStderrWrite(chunk, encoding, callback);
  }
  if (cb) cb();
  return true;
};

const realBin = fs.realpathSync(binPath);
process.argv = [process.execPath, realBin, ...sidecarArgs];

await import(pathToFileURL(realBin).href);
