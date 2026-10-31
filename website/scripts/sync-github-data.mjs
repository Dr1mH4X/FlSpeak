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

function getLocalGitTags() {
  try {
    const out = execSync('git tag --sort=creatordate', {
      cwd: REPO_ROOT,
      stdio: ['ignore', 'pipe', 'ignore'],
      encoding: 'utf8',
    });
    if (!out || !out.trim()) return [];
    return out
      .split(/\r?\n/)
      .map((t) => t.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}

function getTagCommitDate(tag) {
  try {
    return execSync(`git log -1 --format="%ad" --date=short "${tag}^{commit}"`, {
      cwd: REPO_ROOT,
      stdio: ['ignore', 'pipe', 'ignore'],
      encoding: 'utf8',
    }).trim();
  } catch {
    return '';
  }
}

function getCommitsForRange(rangeSpec) {
  try {
    const args = rangeSpec ? ` "${rangeSpec}"` : '';
    const out = execSync(
      `git log --date=short --pretty=format:"%H%x09%ad%x09%s"${args}`,
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

function getLocalGitCommits() {
  return getCommitsForRange(null);
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

function groupCommitsByConventionalType(commits, repoSlug) {
  const groups = {
    breaking: [],
    feat: [],
    fix: [],
    perf: [],
    revert: [],
  };

  for (const commit of commits) {
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

  return groups;
}

function formatRawCommitSections(groups) {
  const lines = [];
  if (groups.breaking.length > 0) {
    lines.push('#### 升级注意', '', ...groups.breaking, '');
  }
  if (groups.feat.length > 0) {
    lines.push('#### 新增', '', ...groups.feat, '');
  }
  if (groups.fix.length > 0) {
    lines.push('#### 修复', '', ...groups.fix, '');
  }
  if (groups.perf.length > 0) {
    lines.push('#### 优化', '', ...groups.perf, '');
  }
  if (groups.revert.length > 0) {
    lines.push('#### 回滚', '', ...groups.revert, '');
  }
  return lines;
}

function getCuratedReleaseNote(tag) {
  const candidates = [
    resolve(REPO_ROOT, 'docs', 'release', `${tag}.md`),
    resolve(REPO_ROOT, 'docs', 'release', `${tag.replace(/^v/i, '')}.md`),
    resolve(REPO_ROOT, 'docs', 'release', `v${tag.replace(/^v/i, '')}.md`),
  ];
  let docPath = null;
  for (const c of candidates) {
    if (existsSync(c)) {
      docPath = c;
      break;
    }
  }
  if (!docPath) return null;

  try {
    const raw = readFileSync(docPath, 'utf8');
    const lines = raw.split(/\r?\n/);
    let title = null;
    let date = null;
    const summaryLines = [];
    const sections = {
      breaking: [],
      feat: [],
      fix: [],
      perf: [],
      other: [],
    };
    const contributors = [];

    let active = null;
    let pastHeader = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;

      if (!pastHeader && line.startsWith('# ')) {
        const m = line.match(
          /^#\s+([^\s(]+)\s*(?:\((\d{4}-\d{2}-\d{2})\))?(?::\s*(.+))?$/
        );
        if (m) {
          date = m[2] || null;
          title = m[3] ? m[3].trim() : null;
          pastHeader = true;
          continue;
        }
      }

      if (line.startsWith('## ')) {
        pastHeader = true;
        const h = line.slice(3).trim();
        if (h.includes('新增')) active = 'feat';
        else if (h.includes('修复')) active = 'fix';
        else if (h.includes('优化')) active = 'perf';
        else if (h.includes('其他')) active = 'other';
        else if (h.includes('升级注意') || h.includes('破坏性'))
          active = 'breaking';
        else if (h.includes('贡献者')) active = 'contributors';
        else active = null;
        continue;
      }

      if (!pastHeader || active === null) {
        summaryLines.push(line);
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('* ')) {
        const item = line.slice(2).trim();
        if (active === 'contributors') {
          contributors.push(item);
        } else if (sections[active]) {
          sections[active].push(item);
        }
      }
    }

    return {
      title,
      date,
      summary: summaryLines.join(' '),
      sections,
      contributors,
    };
  } catch {
    return null;
  }
}

function formatCuratedReleaseSections(curated, rawCommitSections) {
  const lines = [];
  if (curated.summary) {
    lines.push(curated.summary, '');
  }

  if (curated.sections.breaking && curated.sections.breaking.length > 0) {
    lines.push(
      '### 升级注意',
      '',
      ...curated.sections.breaking.map((it) => `* ${it}`),
      ''
    );
  }
  if (curated.sections.feat && curated.sections.feat.length > 0) {
    lines.push(
      '### 新增',
      '',
      ...curated.sections.feat.map((it) => `* ${it}`),
      ''
    );
  }
  if (curated.sections.fix && curated.sections.fix.length > 0) {
    lines.push(
      '### 修复',
      '',
      ...curated.sections.fix.map((it) => `* ${it}`),
      ''
    );
  }
  if (curated.sections.perf && curated.sections.perf.length > 0) {
    lines.push(
      '### 优化',
      '',
      ...curated.sections.perf.map((it) => `* ${it}`),
      ''
    );
  }
  if (curated.sections.other && curated.sections.other.length > 0) {
    lines.push(
      '### 其他',
      '',
      ...curated.sections.other.map((it) => `* ${it}`),
      ''
    );
  }

  if (curated.contributors && curated.contributors.length > 0) {
    lines.push(
      '### 贡献者',
      '',
      ...curated.contributors.map((c) => `* ${c}`),
      ''
    );
  }

  if (rawCommitSections && rawCommitSections.length > 0) {
    lines.push('### Commits', '', ...rawCommitSections);
  }

  return lines;
}

function formatReleaseSections(groups) {
  const lines = [];
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
  return lines;
}

function buildVersionedChangelog(repoSlug) {
  const tags = getLocalGitTags();
  const versions = [];

  // 1. If tags exist, check if there are unreleased commits between latest tag and HEAD
  if (tags.length > 0) {
    const latestTag = tags[tags.length - 1];
    const unreleasedCommits = getCommitsForRange(`${latestTag}..HEAD`);
    if (unreleasedCommits.length > 0) {
      const groups = groupCommitsByConventionalType(unreleasedCommits, repoSlug);
      const total =
        groups.breaking.length +
        groups.feat.length +
        groups.fix.length +
        groups.perf.length +
        groups.revert.length;
      if (total > 0) {
        const headSha = unreleasedCommits[0].sha;
        const headShort = headSha.slice(0, 7).toLowerCase();
        const latestDate = unreleasedCommits[0].date;
        const compareUrl = `https://github.com/${repoSlug}/compare/${latestTag}...HEAD`;
        versions.push({
          header: `## [Unreleased (${headShort})](${compareUrl}) (${latestDate})`,
          sections: formatReleaseSections(groups),
        });
      }
    }

    // 2. Iterate tags in reverse (latest version first)
    for (let i = tags.length - 1; i >= 0; i--) {
      const tag = tags[i];
      const prevTag = i > 0 ? tags[i - 1] : null;
      const rangeSpec = prevTag ? `${prevTag}..${tag}` : tag;
      const tagCommits = getCommitsForRange(rangeSpec);
      const groups = groupCommitsByConventionalType(tagCommits, repoSlug);
      const curated = getCuratedReleaseNote(tag);

      const tagDate =
        curated?.date || getTagCommitDate(tag) || (tagCommits[0]?.date ?? '');
      const tagUrl = prevTag
        ? `https://github.com/${repoSlug}/compare/${prevTag}...${tag}`
        : `https://github.com/${repoSlug}/releases/tag/${tag}`;

      if (curated) {
        const rawCommitSections = formatRawCommitSections(groups);
        const titleSuffix = curated.title ? `: ${curated.title}` : '';
        versions.push({
          header: `## [${tag}](${tagUrl}) (${tagDate})${titleSuffix}`,
          sections: formatCuratedReleaseSections(curated, rawCommitSections),
        });
      } else {
        const total =
          groups.breaking.length +
          groups.feat.length +
          groups.fix.length +
          groups.perf.length +
          groups.revert.length;
        if (total > 0) {
          versions.push({
            header: `## [${tag}](${tagUrl}) (${tagDate})`,
            sections: formatReleaseSections(groups),
          });
        }
      }
    }
  } else {
    // No tags at all: entire commit history as initial unreleased snapshot
    const allCommits = getCommitsForRange(null);
    if (allCommits.length > 0) {
      const groups = groupCommitsByConventionalType(allCommits, repoSlug);
      const total =
        groups.breaking.length +
        groups.feat.length +
        groups.fix.length +
        groups.perf.length +
        groups.revert.length;
      if (total > 0) {
        const headSha = allCommits[0].sha;
        const headShort = headSha.slice(0, 7).toLowerCase();
        const dateStr = allCommits[0].date;
        versions.push({
          header: `## [main@${headShort}](https://github.com/${repoSlug}/commit/${headSha}) (${dateStr})`,
          sections: formatReleaseSections(groups),
        });
      }
    }
  }

  if (versions.length === 0) return '';

  const lines = ['# Changelog', ''];
  for (const v of versions) {
    lines.push(v.header, '');
    lines.push(...v.sections);
  }
  return lines.join('\n');
}

async function main() {
  mkdirSync(PUBLIC_DIR, { recursive: true });
  const repoSlug = detectRepoSlug();

  let stars = null;
  const localTags = getLocalGitTags();
  const latestLocalTag = localTags.length > 0 ? localTags[localTags.length - 1] : null;

  let manifest = {
    repo: repoSlug,
    tag: latestLocalTag,
    name: latestLocalTag,
    publishedAt: latestLocalTag ? getTagCommitDate(latestLocalTag) || null : null,
    htmlUrl: latestLocalTag
      ? `https://github.com/${repoSlug}/releases/tag/${latestLocalTag}`
      : `https://github.com/${repoSlug}/releases`,
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
  // 2. Otherwise generate versioned changelog from git tags and Conventional Commits
  const rootChangelogPath = resolve(REPO_ROOT, 'CHANGELOG.md');
  let changelogMarkdown = '';

  if (existsSync(rootChangelogPath)) {
    changelogMarkdown = readFileSync(rootChangelogPath, 'utf8');
  } else {
    changelogMarkdown = buildVersionedChangelog(repoSlug);
  }

  writeFileSync(resolve(PUBLIC_DIR, 'CHANGELOG.md'), changelogMarkdown, 'utf8');
}

main();
