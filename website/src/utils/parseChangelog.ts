import type {
  ChangelogCategory,
  ChangelogItem,
  ChangelogSection,
  ChangelogVersion,
} from '../types/release';

const CATEGORY_ORDER: ChangelogCategory[] = [
  'breaking',
  'feat',
  'fix',
  'perf',
  'revert',
  'other',
];

function mapHeadingToCategory(heading: string): ChangelogCategory | null {
  const lower = heading.toLowerCase();
  if (
    lower.includes('breaking') ||
    lower.includes('破坏性') ||
    lower.includes('升级注意')
  ) {
    return 'breaking';
  }
  if (
    lower.includes('feature') ||
    lower.includes('feat') ||
    lower.includes('新增') ||
    lower.includes('新功能')
  ) {
    return 'feat';
  }
  if (lower.includes('fix') || lower.includes('bug') || lower.includes('修复')) {
    return 'fix';
  }
  if (
    lower.includes('perf') ||
    lower.includes('optim') ||
    lower.includes('refactor') ||
    lower.includes('优化') ||
    lower.includes('性能')
  ) {
    return 'perf';
  }
  if (
    lower.includes('revert') ||
    lower.includes('回滚') ||
    lower.includes('撤销')
  ) {
    return 'revert';
  }
  if (
    lower.includes('other') ||
    lower.includes('其他') ||
    lower.includes('misc') ||
    lower.includes('chore')
  ) {
    return 'other';
  }
  return null;
}

export function normalizeAnchorId(version: string): string {
  const cleaned = version.trim().replace(/^#/, '');
  if (/^v\d/i.test(cleaned)) {
    return cleaned.replace(/[^a-zA-Z0-9._@-]/g, '-');
  }
  if (/^\d+\.\d+/.test(cleaned)) {
    return `v${cleaned.replace(/[^a-zA-Z0-9._@-]/g, '-')}`;
  }
  return cleaned.replace(/[^a-zA-Z0-9._@-]/g, '-');
}

export function parseBulletLine(
  rawLine: string,
  category: ChangelogCategory,
  index: number,
  repoSlug = 'Dr1mH4X/FlSpeak'
): ChangelogItem | null {
  let text = rawLine.trim().replace(/^[-*+]\s+/, '').trim();
  if (!text) return null;

  let shortHash: string | null = null;
  let commitUrl: string | null = null;

  // Match trailing ([abc1234](https://github.com/.../commit/...))
  const linkHashMatch = text.match(
    /\(\[([a-f0-9]{7,40})\]\((https?:\/\/[^\s)]+)\)\)\s*$/i
  );
  if (linkHashMatch) {
    shortHash = linkHashMatch[1].slice(0, 7).toLowerCase();
    commitUrl = linkHashMatch[2];
    text = text.slice(0, linkHashMatch.index).trim();
  } else {
    // Match trailing (abc1234) or [abc1234]
    const plainHashMatch = text.match(
      /(?:\(|\[)([a-f0-9]{7,40})(?:\)|\])\s*$/i
    );
    if (plainHashMatch) {
      shortHash = plainHashMatch[1].slice(0, 7).toLowerCase();
      commitUrl = `https://github.com/${repoSlug}/commit/${plainHashMatch[1]}`;
      text = text.slice(0, plainHashMatch.index).trim();
    }
  }

  let scope: string | null = null;

  // Match **scope:** description or **scope**: description
  const boldScopeMatch = text.match(/^\*\*([^*:]+):?\*\*:?\s*(.+)$/);
  if (boldScopeMatch) {
    scope = boldScopeMatch[1].trim();
    text = boldScopeMatch[2].trim();
  } else {
    // Match conventional commit prefix inside bullet: feat(scope): description
    const convMatch = text.match(/^([a-zA-Z]+)(?:\(([^)]+)\))?!?:\s*(.+)$/);
    if (convMatch) {
      if (convMatch[2]) scope = convMatch[2].trim();
      text = convMatch[3].trim();
    }
  }

  // Strip any leftover markdown links in description while keeping link label
  text = text.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '$1').trim();
  if (!text) return null;

  return {
    id: `${category}-${index}-${shortHash || text.slice(0, 16)}`,
    category,
    scope,
    description: text,
    shortHash,
    commitUrl,
  };
}

export function parseChangelogMarkdown(
  markdown: string,
  repoSlug = 'Dr1mH4X/FlSpeak'
): ChangelogVersion[] {
  if (!markdown || !markdown.trim()) return [];

  const lines = markdown.split(/\r?\n/);
  const versions: ChangelogVersion[] = [];

  let currentVersion: ChangelogVersion | null = null;
  let currentBuckets: Record<ChangelogCategory, ChangelogItem[]> = {
    breaking: [],
    feat: [],
    fix: [],
    perf: [],
    revert: [],
    other: [],
  };
  let rawBuckets: Record<ChangelogCategory, ChangelogItem[]> = {
    breaking: [],
    feat: [],
    fix: [],
    perf: [],
    revert: [],
    other: [],
  };
  let currentSummaryLines: string[] = [];
  let currentContributors: string[] = [];
  let mode: 'curated' | 'contributors' | 'rawCommits' = 'curated';
  let activeCategory: ChangelogCategory = 'feat';
  let hasSeenSubHeading = false;
  let itemCounter = 0;

  function flushCurrent() {
    if (!currentVersion) return;
    const sections: ChangelogSection[] = [];
    for (const cat of CATEGORY_ORDER) {
      if (currentBuckets[cat] && currentBuckets[cat].length > 0) {
        sections.push({
          category: cat,
          items: currentBuckets[cat],
        });
      }
    }
    const rawSections: ChangelogSection[] = [];
    for (const cat of CATEGORY_ORDER) {
      if (rawBuckets[cat] && rawBuckets[cat].length > 0) {
        rawSections.push({
          category: cat,
          items: rawBuckets[cat],
        });
      }
    }
    if (sections.length > 0 || rawSections.length > 0) {
      currentVersion.sections = sections;
      currentVersion.rawSections =
        rawSections.length > 0 ? rawSections : undefined;
      currentVersion.summary =
        currentSummaryLines.length > 0
          ? currentSummaryLines.join(' ').trim()
          : null;
      currentVersion.contributors =
        currentContributors.length > 0 ? currentContributors : undefined;
      versions.push(currentVersion);
    }
    currentVersion = null;
    currentSummaryLines = [];
    currentContributors = [];
    currentBuckets = {
      breaking: [],
      feat: [],
      fix: [],
      perf: [],
      revert: [],
      other: [],
    };
    rawBuckets = {
      breaking: [],
      feat: [],
      fix: [],
      perf: [],
      revert: [],
      other: [],
    };
    mode = 'curated';
    activeCategory = 'feat';
    hasSeenSubHeading = false;
  }

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    // Match version header:
    // ## [0.2.0](https://...) (2026-10-25)
    // ## v0.2.0 (2026-10-25)
    // # 0.2.0 (2026-10-25): Title
    const headerMatch = line.match(
      /^#{1,2}\s+(?:\[([^\]]+)\]\(([^)]+)\)|([^\s(]+))\s*(?:\((\d{4}-\d{2}-\d{2})\))?(?::\s*(.+))?$/
    );

    if (
      headerMatch &&
      !line.startsWith('###') &&
      (headerMatch[1] || headerMatch[3])
    ) {
      const rawVer = (headerMatch[1] || headerMatch[3] || '').trim();
      if (/^changelog$/i.test(rawVer)) {
        continue;
      }

      flushCurrent();
      const compareUrl = headerMatch[2] ? headerMatch[2].trim() : null;
      const date = headerMatch[4] ? headerMatch[4].trim() : '';
      const year = date ? date.slice(0, 4) : '';
      const isTagRelease = /^v?\d+\.\d+/i.test(rawVer);
      const displayVersion = isTagRelease
        ? rawVer.startsWith('v')
          ? rawVer
          : `v${rawVer}`
        : rawVer;
      const title = headerMatch[5] ? headerMatch[5].trim() : null;

      currentVersion = {
        version: displayVersion,
        anchorId: normalizeAnchorId(displayVersion),
        date,
        year,
        compareUrl,
        isTagRelease,
        title,
        summary: null,
        contributors: undefined,
        sections: [],
        rawSections: undefined,
      };
      currentBuckets = {
        breaking: [],
        feat: [],
        fix: [],
        perf: [],
        revert: [],
        other: [],
      };
      rawBuckets = {
        breaking: [],
        feat: [],
        fix: [],
        perf: [],
        revert: [],
        other: [],
      };
      currentSummaryLines = [];
      currentContributors = [];
      mode = 'curated';
      activeCategory = 'feat';
      hasSeenSubHeading = false;
      continue;
    }

    const subHeadingMatch = line.match(/^#{2,4}\s+(.+)$/);
    if (subHeadingMatch && currentVersion) {
      hasSeenSubHeading = true;
      const subTitle = subHeadingMatch[1].trim();
      const lower = subTitle.toLowerCase();
      if (lower.includes('贡献者') || lower.includes('contributors')) {
        mode = 'contributors';
      } else if (lower.includes('commits') || lower.includes('提交')) {
        mode = 'rawCommits';
        activeCategory = 'feat';
      } else {
        const mapped = mapHeadingToCategory(subTitle);
        if (mapped) {
          activeCategory = mapped;
        }
      }
      continue;
    }

    if (
      !line.startsWith('#') &&
      !/^[-*+]\s+/.test(line) &&
      currentVersion &&
      !hasSeenSubHeading
    ) {
      currentSummaryLines.push(line);
      continue;
    }

    if (/^[-*+]\s+/.test(line) && currentVersion) {
      if (mode === 'contributors') {
        const c = line.replace(/^[-*+]\s+/, '').trim();
        if (c) currentContributors.push(c);
      } else if (mode === 'rawCommits') {
        const item = parseBulletLine(
          line,
          activeCategory,
          ++itemCounter,
          repoSlug
        );
        if (item) {
          rawBuckets[activeCategory].push(item);
        }
      } else {
        const item = parseBulletLine(
          line,
          activeCategory,
          ++itemCounter,
          repoSlug
        );
        if (item) {
          currentBuckets[activeCategory].push(item);
        }
      }
    }
  }

  flushCurrent();
  return versions;
}

export interface RawCommitInput {
  sha: string;
  date: string;
  message: string;
}

export function buildChangelogFromCommits(
  commits: RawCommitInput[],
  repoSlug = 'Dr1mH4X/FlSpeak'
): ChangelogVersion[] {
  if (!Array.isArray(commits) || commits.length === 0) return [];

  const byDate = new Map<string, RawCommitInput[]>();
  for (const c of commits) {
    if (!c.sha || !c.message) continue;
    const dateStr = (c.date || '').slice(0, 10);
    if (!dateStr) continue;
    const list = byDate.get(dateStr) || [];
    list.push(c);
    byDate.set(dateStr, list);
  }

  const versions: ChangelogVersion[] = [];
  let counter = 0;

  for (const [dateStr, dayCommits] of byDate.entries()) {
    const buckets: Record<ChangelogCategory, ChangelogItem[]> = {
      breaking: [],
      feat: [],
      fix: [],
      perf: [],
      revert: [],
      other: [],
    };

    for (const commit of dayCommits) {
      const [subjectLine, ...bodyLines] = commit.message.split(/\r?\n/);
      const subject = (subjectLine || '').trim();
      const body = bodyLines.join('\n');
      if (!subject) continue;

      let category: ChangelogCategory | null = null;
      let scope: string | null = null;
      let description = subject;

      if (/^revert\b/i.test(subject)) {
        category = 'revert';
        description = subject.replace(/^revert[:\s"]*/i, '').replace(/"$/, '');
      } else {
        const m = subject.match(/^([a-zA-Z]+)(?:\(([^)]+)\))?(!)?:\s*(.+)$/);
        if (!m) continue;
        const type = m[1].toLowerCase();
        scope = m[2] ? m[2].trim() : null;
        const breaking = Boolean(m[3]) || /BREAKING[\s-]CHANGE:/i.test(body);
        description = m[4].trim();

        if (breaking) category = 'breaking';
        else if (type === 'feat') category = 'feat';
        else if (type === 'fix') category = 'fix';
        else if (type === 'perf' || type === 'refactor' || type === 'style') {
          category = 'perf';
        } else if (type === 'revert') {
          category = 'revert';
        }
      }

      if (!category || !description) continue;
      const shortHash = commit.sha.slice(0, 7).toLowerCase();
      buckets[category].push({
        id: `${category}-${++counter}-${shortHash}`,
        category,
        scope,
        description,
        shortHash,
        commitUrl: `https://github.com/${repoSlug}/commit/${commit.sha}`,
      });
    }

    const sections: ChangelogSection[] = [];
    for (const cat of CATEGORY_ORDER) {
      if (buckets[cat] && buckets[cat].length > 0) {
        sections.push({ category: cat, items: buckets[cat] });
      }
    }

    if (sections.length > 0) {
      const headSha = dayCommits[0].sha;
      const headShort = headSha.slice(0, 7).toLowerCase();
      const versionLabel = `main@${headShort}`;
      versions.push({
        version: versionLabel,
        anchorId: normalizeAnchorId(versionLabel),
        date: dateStr,
        year: dateStr.slice(0, 4),
        compareUrl: `https://github.com/${repoSlug}/commit/${headSha}`,
        isTagRelease: false,
        sections,
      });
    }
  }

  return versions;
}

export interface FilteredChangelogResult {
  versions: ChangelogVersion[];
  matchedVersionsCount: number;
  matchedItemsCount: number;
}

export function filterChangelogVersions(
  versions: ChangelogVersion[],
  rawQuery: string
): FilteredChangelogResult {
  const query = rawQuery.trim().toLowerCase();
  if (!query) {
    const totalItems = versions.reduce(
      (sum, v) =>
        sum +
        v.sections.reduce((sSum, sec) => sSum + sec.items.length, 0) +
        (v.rawSections?.reduce((rSum, sec) => rSum + sec.items.length, 0) ?? 0),
      0
    );
    return {
      versions,
      matchedVersionsCount: versions.length,
      matchedItemsCount: totalItems,
    };
  }

  const filtered: ChangelogVersion[] = [];
  let matchedItemsCount = 0;

  for (const v of versions) {
    const versionMatches =
      v.version.toLowerCase().includes(query) ||
      v.date.toLowerCase().includes(query) ||
      (v.title?.toLowerCase().includes(query) ?? false) ||
      (v.summary?.toLowerCase().includes(query) ?? false);

    const filterSecList = (sectionsList: ChangelogSection[]) => {
      const result: ChangelogSection[] = [];
      for (const sec of sectionsList) {
        const items = sec.items.filter((item) => {
          if (versionMatches) return true;
          const inScope = item.scope?.toLowerCase().includes(query) ?? false;
          const inDesc = item.description.toLowerCase().includes(query);
          const inHash = item.shortHash?.toLowerCase().includes(query) ?? false;
          return inScope || inDesc || inHash;
        });
        if (items.length > 0) {
          result.push({ category: sec.category, items });
          matchedItemsCount += items.length;
        }
      }
      return result;
    };

    const matchedSections = filterSecList(v.sections);
    const matchedRawSections = v.rawSections
      ? filterSecList(v.rawSections)
      : [];

    if (
      versionMatches ||
      matchedSections.length > 0 ||
      matchedRawSections.length > 0
    ) {
      filtered.push({
        ...v,
        sections: matchedSections,
        rawSections:
          matchedRawSections.length > 0 ? matchedRawSections : undefined,
      });
    }
  }

  return {
    versions: filtered,
    matchedVersionsCount: filtered.length,
    matchedItemsCount,
  };
}

export interface HighlightSegment {
  text: string;
  highlighted: boolean;
}

export function splitHighlightSegments(
  text: string,
  rawQuery: string
): HighlightSegment[] {
  const query = rawQuery.trim();
  if (!query || !text) {
    return [{ text, highlighted: false }];
  }

  const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(`(${escaped})`, 'gi');
  const parts = text.split(regex);
  const segments: HighlightSegment[] = [];

  for (const part of parts) {
    if (!part) continue;
    segments.push({
      text: part,
      highlighted: part.toLowerCase() === query.toLowerCase(),
    });
  }
  return segments.length > 0 ? segments : [{ text, highlighted: false }];
}
