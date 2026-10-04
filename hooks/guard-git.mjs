#!/usr/bin/env node
// PreToolUse guard for Bash/PowerShell: blocks git writes to protected branches and pushes, but only inside
// repos that use addin-batch (<main repo>/.harness/addin-batch.json with lanes.protectedBranches).
// Everywhere else it exits 0 immediately. Exit code 2 = block; the reason goes to stderr for Claude.
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const WRITE_ON_CURRENT = new Set(['commit', 'merge', 'rebase', 'reset', 'cherry-pick', 'revert', 'am', 'pull']);
const BRANCH_WRITE_FLAGS = new Set(['-d', '-D', '--delete', '-f', '--force', '-m', '-M', '--move', '-c', '-C', '--copy']);

function readInput() {
  try {
    return JSON.parse(readFileSync(0, 'utf8'));
  } catch {
    return null;
  }
}

function git(dir, args) {
  try {
    return execFileSync('git', ['-C', dir, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

function loadPolicy(dir) {
  const common = git(dir, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
  if (!common) return null;
  const root = path.basename(common) === '.git' ? path.dirname(common) : null;
  if (!root) return null;
  const file = path.join(root, '.harness', 'addin-batch.json');
  if (!existsSync(file)) return null;
  try {
    const lanes = JSON.parse(readFileSync(file, 'utf8')).lanes ?? {};
    if (!Array.isArray(lanes.protectedBranches) || lanes.protectedBranches.length === 0) return null;
    const patterns = lanes.protectedBranches.map(p =>
      new RegExp('^' + p.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$', 'i'));
    return { patterns, push: lanes.push === true, names: lanes.protectedBranches };
  } catch {
    return null;
  }
}

// Shell-ish tokenizer: whitespace split, quotes kept together, segments split on && || ; | and newlines.
function segments(command) {
  const out = [];
  let cur = [], tok = '', quote = null;
  const flushTok = () => { if (tok !== '') { cur.push(tok); tok = ''; } };
  const flushSeg = () => { flushTok(); if (cur.length) out.push(cur); cur = []; };
  for (let i = 0; i < command.length; i++) {
    const c = command[i];
    if (quote) {
      if (c === quote) quote = null; else tok += c;
    } else if (c === '"' || c === "'") {
      quote = c;
    } else if (c === '\n' || c === ';') {
      flushSeg();
    } else if ((c === '&' || c === '|') ) {
      if (command[i + 1] === c) i++;
      flushSeg();
    } else if (/\s/.test(c)) {
      flushTok();
    } else {
      tok += c;
    }
  }
  flushSeg();
  return out;
}

function stripRef(name) {
  return name.replace(/^\+/, '').replace(/^refs\/heads\//, '').replace(/^(origin|upstream)\//, '');
}

function check(input) {
  const command = input?.tool_input?.command;
  if (typeof command !== 'string' || !/\bgit\b/.test(command)) return null;

  let dir = input.cwd || process.cwd();
  const policy = loadPolicy(dir);
  if (!policy) return null;
  const isProtected = name => name && policy.patterns.some(re => re.test(stripRef(name)));

  for (const seg of segments(command)) {
    if (seg[0] === 'cd' || seg[0] === 'Set-Location' || seg[0] === 'pushd') {
      if (seg[1]) dir = path.resolve(dir, seg[1]);
      continue;
    }
    const g = seg.findIndex(t => t === 'git' || t === 'git.exe' || /[\\/]git(\.exe)?$/i.test(t));
    if (g < 0) continue;

    let gitDir = dir, i = g + 1;
    while (i < seg.length && seg[i].startsWith('-')) {
      if (seg[i] === '-C') { gitDir = path.resolve(dir, seg[i + 1] ?? ''); i += 2; }
      else if (seg[i] === '-c') { i += 2; }
      else i++;
    }
    const sub = seg[i];
    const args = seg.slice(i + 1);
    if (!sub) continue;

    if (sub === 'push') {
      if (!policy.push) return 'git push is disabled for this batch (addin-batch lanes.push = false). The user pushes.';
      const target = args.filter(a => !a.startsWith('-')).slice(1).map(a => a.split(':').pop());
      const current = git(gitDir, ['rev-parse', '--abbrev-ref', 'HEAD']);
      if (target.some(isProtected) || (target.length === 0 && isProtected(current)))
        return `git push to a protected branch (${policy.names.join(', ')}) is not allowed.`;
      continue;
    }

    if (WRITE_ON_CURRENT.has(sub)) {
      const current = git(gitDir, ['rev-parse', '--abbrev-ref', 'HEAD']);
      if (isProtected(current))
        return `git ${sub} while '${current}' is checked out: protected branches (${policy.names.join(', ')}) are never written by agents. Work on the batch branch.`;
      continue;
    }

    if (sub === 'branch' && args.some(a => BRANCH_WRITE_FLAGS.has(a)) && args.some(a => !a.startsWith('-') && isProtected(a)))
      return `git branch would modify a protected branch (${policy.names.join(', ')}).`;

    if (sub === 'update-ref' && args.some(a => /^refs\/heads\//.test(a) && isProtected(a)))
      return `git update-ref on a protected branch (${policy.names.join(', ')}) is not allowed.`;

    if ((sub === 'checkout' || sub === 'switch' || sub === 'worktree') ) {
      const force = args.findIndex(a => a === '-B' || a === '-C' || a === '--force-create');
      if (force >= 0 && isProtected(args[force + 1]))
        return `git ${sub} would reset a protected branch (${policy.names.join(', ')}).`;
    }
  }
  return null;
}

const reason = check(readInput());
if (reason) {
  process.stderr.write(`[hicas-bimcad guard-git] ${reason}\n`);
  process.exit(2);
}
process.exit(0);
