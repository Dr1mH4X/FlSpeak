#!/usr/bin/env node
/**
 * Build-time data synchronization script for FlSpeak website.
 * Extracts real repository metadata, releases, and commit history from local git
 * and/or GitHub REST API, writing:
 *   - website/public/release.json
 *   - website/public/CHANGELOG.md
 *
 * Strictly zero fabricated data: if no formal release exists, release.json has
 * tag: null and assets: [].
 */

import { execSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WEBSITE_ROOT = resolve(__dirname, '..');
const REPO_ROOT = resolve(WEBSITE_ROOT, '..');
const PUBLIC_DIR = resolve(WEBSITE_ROOT, 'public');

const DEFAULT_REPO = 'Dr1mH4X/FlSpeak';

function detectRepoSlug() {
  if (process.env.GITHUB_REPOSITORY) {
    return process.env.GITHUB_REPOSITORY.trim();
  }
  try {
    const remote = execSync('git config --get remote.origin.url', {
      cwd: REPO_ROOT,
      stdio: ['ignore', 'pipe', 'ignore'],
      encoding: 'utf8',
    }).trim();
    const match = remote.match(/github\.com[:/]([^/]+\/[^/.]+)(?:\.git)?$/i);
    if (match) return match[1];
  } catch {
    // Not a git checkout or no remote.origin.url
  }

  try {
    const aboutCardPath = resolve(
      REPO_ROOT,
      'lib/features/settings/widgets/about_card.dart'
    );
    if (existsSync(aboutCardPath)) {
      const content = readFileSync(aboutCardPath, 'utf8');
      const match = content.match(/https:\/\/github\.com\/([^/]+\/[^/'"]+)/);
      if (match) return match[1];
    }
  } catch {
    // Ignore
  }

  return DEFAULT_REPO;
}

function getLocalGitCommits() {
  try {
    const out = execSync(
      'git log -n 200 --date=short --pretty=format:"%H%x09%ad%x09%s"',
      {
        cwd: REPO_ROOT,
        stdio: ['ignore', 'pipe', 'ignore'],
        encoding: 'utf8',
      }
    );
    if (!out || !out.trim()) return [];
    return out
      .split(/\r?\n/)
      .map((line) => {
        const [sha, date, ...rest] = line.split('\t');
        const message = rest.join('\t').trim();
        return sha && date && message ? { sha, date, message } : null;
      })
      .filter(Boolean);
  } catch {
    return [];
  }
}

async function fetchJson(url) {
  const headers = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'flspeak-website-sync',
  };
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(url, { headers });
  if (!res.ok) return null;
  return await res.json();
}

function formatCommitsToMarkdown(commits, repoSlug) {
  if (!Array.isArray(commits) || commits.length === 0) return '';

  const byDate = new Map();
  for (const c of commits) {
    if (!c.sha || !c.message) continue;
    const dateStr = c.date.slice(0, 10);
    if (!dateStr) continue;
    const arr = byDate.get(dateStr) || [];
    arr.push(c);
    byDate.set(dateStr, arr);
  }

  const lines = ['# Changelog', ''];

  for (const [dateStr, dayCommits] of byDate.entries()) {
    const groups = {
      breaking: [],
      feat: [],
      fix: [],
      perf: [],
      revert: [],
    };

    for (const commit of dayCommits) {
      const subject = commit.message.split(/\r?\n/)[0].trim();
      const shortSha = commit.sha.slice(0, 7).toLowerCase();
      const commitUrl = `https://github.com/${repoSlug}/commit/${commit.sha}`;

      if (/^revert\b/i.test(subject)) {
        const desc = subject.replace(/^revert[:\s"]*/i, '').replace(/"$/, '');
        groups.revert.push(`* ${desc} ([${shortSha}](${commitUrl}))`);
        continue;
      }

      const m = subject.match(/^([a-zA-Z]+)(?:\(([^)]+)\))?(!)?:\s*(.+)$/);
      if (!m) continue;
      const type = m[1].toLowerCase();
      const scope = m[2] ? m[2].trim() : null;
      const isBreaking =
        Boolean(m[3]) || /BREAKING[\s-]CHANGE:/i.test(commit.message);
      const desc = m[4].trim();

      let bucket = null;
      if (isBreaking) bucket = 'breaking';
      else if (type === 'feat') bucket = 'feat';
      else if (type === 'fix') bucket = 'fix';
      else if (type === 'perf' || type === 'refactor' || type === 'style') {
        bucket = 'perf';
      } else if (type === 'revert') {
        bucket = 'revert';
      }
      if (!bucket) continue;

      const scopePrefix = scope ? `**${scope}:** ` : '';
      groups[bucket].push(
        `* ${scopePrefix}${desc} ([${shortSha}](${commitUrl}))`
      );
    }

    const totalInDay =
      groups.breaking.length +
      groups.feat.length +
      groups.fix.length +
      groups.perf.length +
      groups.revert.length;

    if (totalInDay === 0) continue;

    const headSha = dayCommits[0].sha;
    const headShort = headSha.slice(0, 7).toLowerCase();
    lines.push(
      `## [main@${headShort}](https://github.com/${repoSlug}/commit/${headSha}) (${dateStr})`,
      ''
    );

    if (groups.breaking.length > 0) {
      lines.push('### Breaking Changes', '', ...groups.breaking, '');
    }
    if (groups.feat.length > 0) {
      lines.push('### Features', '', ...groups.feat, '');
    }
    if (groups.fix.length > 0) {
      lines.push('### Bug Fixes', '', ...groups.fix, '');
    }
    if (groups.perf.length > 0) {
      lines.push('### Performance', '', ...groups.perf, '');
    }
    if (groups.revert.length > 0) {
      lines.push('### Reverts', '', ...groups.revert, '');
    }
  }

  return lines.join('\n');
}

async function main() {
  mkdirSync(PUBLIC_DIR, { recursive: true });
  const repoSlug = detectRepoSlug();

  let stars = null;
  let manifest = {
    repo: repoSlug,
    tag: null,
    name: null,
    publishedAt: null,
    htmlUrl: `https://github.com/${repoSlug}/releases`,
    stars: null,
    sha256SumsUrl: null,
    assets: [],
  };

  try {
    const [repoInfo, releases] = await Promise.all([
      fetchJson(`https://api.github.com/repos/${repoSlug}`),
      fetchJson(`https://api.github.com/repos/${repoSlug}/releases?per_page=10`),
    ]);

    if (repoInfo && typeof repoInfo.stargazers_count === 'number') {
      stars = repoInfo.stargazers_count;
      manifest.stars = stars;
    }

    if (Array.isArray(releases) && releases.length > 0) {
      const chosen =
        releases.find((r) => !r.draft && !r.prerelease) ||
        releases.find((r) => !r.draft) ||
        releases[0];

      if (chosen) {
        let sha256SumsUrl = null;
        const assets = [];
        for (const a of chosen.assets || []) {
          if (/sha256sums/i.test(a.name)) {
            sha256SumsUrl = a.browser_download_url;
          }
          let sha256 = null;
          if (typeof a.digest === 'string' && a.digest.startsWith('sha256:')) {
            sha256 = a.digest.slice('sha256:'.length);
          }
          assets.push({
            name: a.name,
            size: a.size,
            browser_download_url: a.browser_download_url,
            content_type: a.content_type,
            sha256,
          });
        }

        manifest = {
          repo: repoSlug,
          tag: chosen.tag_name || null,
          name: chosen.name || chosen.tag_name || null,
          publishedAt: chosen.published_at || chosen.created_at || null,
          htmlUrl:
            chosen.html_url || `https://github.com/${repoSlug}/releases`,
          stars,
          sha256SumsUrl,
          assets,
        };
      }
    }
  } catch {
    // Offline or API rate-limited; keep honest empty manifest
  }

  writeFileSync(
    resolve(PUBLIC_DIR, 'release.json'),
    JSON.stringify(manifest, null, 2) + '\n',
    'utf8'
  );

  // Sync CHANGELOG.md:
  // 1. Check root CHANGELOG.md if present
  // 2. Otherwise read local git log
  // 3. Otherwise fetch real commits from GitHub REST API
  const rootChangelogPath = resolve(REPO_ROOT, 'CHANGELOG.md');
  let changelogMarkdown = '';

  if (existsSync(rootChangelogPath)) {
    changelogMarkdown = readFileSync(rootChangelogPath, 'utf8');
  } else {
    let commits = getLocalGitCommits();
    if (commits.length === 0) {
      try {
        const apiCommits = await fetchJson(
          `https://api.github.com/repos/${repoSlug}/commits?per_page=100`
        );
        if (Array.isArray(apiCommits)) {
          commits = apiCommits
            .map((item) => {
              const sha = item?.sha;
              const message = item?.commit?.message;
              const date =
                item?.commit?.committer?.date ||
                item?.commit?.author?.date ||
                '';
              return sha && message
                ? { sha, date: date.slice(0, 10), message }
                : null;
            })
            .filter(Boolean);
        }
      } catch {
        // Offline
      }
    }
    changelogMarkdown = formatCommitsToMarkdown(commits, repoSlug);
  }

  writeFileSync(resolve(PUBLIC_DIR, 'CHANGELOG.md'), changelogMarkdown, 'utf8');
}

main();
