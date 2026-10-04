#!/usr/bin/env node
// Prints the branch user for addin-batch, derived from this machine's git user.name (repo config first, then global):
//   {"gitUserName":"Lê Phi Long","branchUser":"lephilong"}
// ASCII lowercase, Vietnamese diacritics removed (đ → d), only [a-z0-9.-], validated with `git check-ref-format`.
// Exit 1 with a message on stderr when user.name is missing or cannot become a valid branch name.
import { execFileSync } from 'node:child_process';

const git = (...args) => {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
};

export function toBranchUser(name) {
  return name
    .replace(/[đĐ]/g, 'd')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9.-]+/g, '')
    .replace(/\.{2,}/g, '.')
    .replace(/^[.-]+|[.-]+$/g, '');
}

const raw = git('config', 'user.name');
if (!raw) {
  console.error('git user.name is not set on this machine. Set it first: git config --global user.name "<tên>"');
  process.exit(1);
}

const branchUser = toBranchUser(raw);
if (!branchUser || !git('check-ref-format', '--branch', `${branchUser}_20000101_lane1`)) {
  console.error(`git user.name "${raw}" cannot be turned into a branch name; ask the user for one (a-z, 0-9, . -).`);
  process.exit(1);
}

console.log(JSON.stringify({ gitUserName: raw, branchUser }));
