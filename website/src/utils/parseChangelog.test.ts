import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseHashRoute } from '../hooks/useUrlState.ts';
import { formatTranslation, translations } from '../i18n/translations.ts';
import {
  classifyAllAssets,
  classifyReleaseAsset,
  findRecommendedAsset,
  formatBytesToMb,
  parseArchFromStrings,
  parseOsFromUserAgent,
} from './detectDevice.ts';
import {
  buildChangelogFromCommits,
  filterChangelogVersions,
  parseChangelogMarkdown,
  splitHighlightSegments,
} from './parseChangelog.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));

test('parseChangelogMarkdown extracts version headers, categories, scopes, and commit hashes', () => {
  const md = `# Changelog

## [0.2.0](https://github.com/Dr1mH4X/FlSpeak/compare/v0.1.0...v0.2.0) (2026-10-29)

### Breaking Changes

* **proto:** enforce strict self-hosted suffix boundary ([a1b2c3d](https://github.com/Dr1mH4X/FlSpeak/commit/a1b2c3d4e5f60000))

### Features

* **audio:** add dual-thread full-duplex cpal engine (f9e8d7c)

### Bug Fixes

* fix reconnect actor race condition
`;

  const parsed = parseChangelogMarkdown(md);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].version, 'v0.2.0');
  assert.equal(parsed[0].anchorId, 'v0.2.0');
  assert.equal(parsed[0].date, '2026-10-29');
  assert.equal(parsed[0].year, '2026');
  assert.equal(parsed[0].isTagRelease, true);
  assert.equal(parsed[0].sections.length, 3);

  const breaking = parsed[0].sections[0];
  assert.equal(breaking.category, 'breaking');
  assert.equal(breaking.items[0].scope, 'proto');
  assert.equal(
    breaking.items[0].description,
    'enforce strict self-hosted suffix boundary'
  );
  assert.equal(breaking.items[0].shortHash, 'a1b2c3d');

  const feat = parsed[0].sections[1];
  assert.equal(feat.category, 'feat');
  assert.equal(feat.items[0].scope, 'audio');
  assert.equal(feat.items[0].shortHash, 'f9e8d7c');
});

test('buildChangelogFromCommits groups conventional commits by date and filters non-conventional noise', () => {
  const commits = [
    {
      sha: '13a27739988776655',
      date: '2026-10-31',
      message: 'feat(workspace): add voice activity ribbon meter',
    },
    {
      sha: '99887766554433221',
      date: '2026-10-31',
      message: 'fix(session)!: serialize client calls in LocalSet actor',
    },
    {
      sha: '00000000000000000',
      date: '2026-10-31',
      message: 'Merge pull request #12 from feature/branch',
    },
  ];

  const versions = buildChangelogFromCommits(commits);
  assert.equal(versions.length, 1);
  assert.equal(versions[0].version, 'main@13a2773');
  assert.equal(versions[0].isTagRelease, false);
  assert.equal(versions[0].sections.length, 2);
  assert.equal(versions[0].sections[0].category, 'breaking');
  assert.equal(versions[0].sections[1].category, 'feat');
});

test('filterChangelogVersions and splitHighlightSegments accurately filter and highlight matches', () => {
  const versions = buildChangelogFromCommits([
    {
      sha: '13a27739988776655',
      date: '2026-10-31',
      message: 'feat(audio): add Opus softclip limiter',
    },
    {
      sha: 'ef10a219988776655',
      date: '2026-10-30',
      message: 'fix(ui): preserve workspace state on theme switch',
    },
  ]);

  const res = filterChangelogVersions(versions, 'opus');
  assert.equal(res.matchedVersionsCount, 1);
  assert.equal(res.matchedItemsCount, 1);
  assert.equal(res.versions[0].version, 'main@13a2773');

  const segs = splitHighlightSegments('add Opus softclip limiter', 'opus');
  assert.equal(segs.length, 3);
  assert.deepEqual(segs[1], { text: 'Opus', highlighted: true });
});

test('classifyReleaseAsset and findRecommendedAsset classify setup.dart artifacts accurately', () => {
  const rawAssets = [
    {
      name: 'FlSpeak-0.2.0-windows-x64.zip',
      size: 18 * 1024 * 1024,
      browser_download_url: 'https://example.com/win.zip',
    },
    {
      name: 'FlSpeak-0.2.0-windows-x64-setup.exe',
      size: 14.5 * 1024 * 1024,
      browser_download_url: 'https://example.com/win.exe',
    },
    {
      name: 'FlSpeak-0.2.0-macos-arm64.app.tar.gz',
      size: 16 * 1024 * 1024,
      browser_download_url: 'https://example.com/mac.tar.gz',
    },
    {
      name: 'FlSpeak-0.2.0-linux-x64.tar.gz',
      size: 15 * 1024 * 1024,
      browser_download_url: 'https://example.com/linux.tar.gz',
    },
    {
      name: 'FlSpeak-0.2.0-android-arm64.apk',
      size: 22 * 1024 * 1024,
      browser_download_url: 'https://example.com/android.apk',
    },
    {
      name: 'SHA256SUMS.txt',
      size: 512,
      browser_download_url: 'https://example.com/SHA256SUMS.txt',
    },
  ];

  assert.equal(classifyReleaseAsset(rawAssets[5]), null);

  const classified = classifyAllAssets(rawAssets);
  assert.equal(classified.length, 5);

  const winRec = findRecommendedAsset(classified, 'windows', 'x64');
  assert.ok(winRec);
  assert.equal(winRec.badge, 'EXE');
  assert.equal(winRec.recommended, true);

  const macRec = findRecommendedAsset(classified, 'macos', 'arm64');
  assert.ok(macRec);
  assert.equal(macRec.platform, 'macos');
  assert.equal(macRec.macChip, 'apple-silicon');
  assert.equal(macRec.recommended, true);

  assert.equal(formatBytesToMb(15728640), '15.0 MB');
  assert.equal(
    parseOsFromUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)'),
    'macos'
  );
  assert.equal(parseArchFromStrings('Linux aarch64'), 'arm64');
});

test('bilingual translations and real synced CHANGELOG.md satisfy brand and zero-fabrication invariants', () => {
  assert.equal(translations.zh.appTitle, 'FlSpeak');
  assert.equal(translations.en.appTitle, 'FlSpeak');
  assert.equal(
    translations.en.heroLede,
    'Yet another teamspeak client, multi-platform and open-source.'
  );
  assert.equal(
    translations.zh.heroLede,
    '另一个多平台、开源的 TeamSpeak 客户端。'
  );
  assert.equal(
    formatTranslation('en', 'ctaDownloadFor', { platform: 'macOS' }),
    'Download for macOS'
  );

  const syncedChangelogPath = resolve(__dirname, '../../public/CHANGELOG.md');
  const syncedMarkdown = readFileSync(syncedChangelogPath, 'utf8');
  const parsedReal = parseChangelogMarkdown(syncedMarkdown);
  assert.ok(
    parsedReal.length >= 1,
    `Expected at least 1 version release node, got ${parsedReal.length}`
  );
  assert.equal(parsedReal[0].year, '2026');
  assert.equal(parsedReal[0].title, '首个正式版本发布');
  assert.ok(parsedReal[0].summary?.includes('FlSpeak 的首个正式版本'));
  assert.deepEqual(parsedReal[0].contributors, ['@Dr1mH4X', '@ZeroBlock0']);
  assert.ok(
    parsedReal[0].rawSections && parsedReal[0].rawSections.length > 0,
    'Expected rawSections commits to be present'
  );
});

test('parseHashRoute accurately routes home, changelog, and deep version anchors', () => {
  assert.deepEqual(parseHashRoute(''), {
    view: 'home',
    targetVersion: null,
    anchor: null,
  });
  assert.deepEqual(parseHashRoute('#/'), {
    view: 'home',
    targetVersion: null,
    anchor: null,
  });
  assert.deepEqual(parseHashRoute('#download'), {
    view: 'home',
    targetVersion: null,
    anchor: 'download',
  });
  assert.deepEqual(parseHashRoute('#/changelog'), {
    view: 'changelog',
    targetVersion: null,
    anchor: null,
  });
  assert.deepEqual(parseHashRoute('#changelog'), {
    view: 'changelog',
    targetVersion: null,
    anchor: null,
  });
  assert.deepEqual(parseHashRoute('#/changelog?v=v0.1.0'), {
    view: 'changelog',
    targetVersion: 'v0.1.0',
    anchor: null,
  });
  assert.deepEqual(parseHashRoute('#/changelog/v0.1.0'), {
    view: 'changelog',
    targetVersion: 'v0.1.0',
    anchor: null,
  });
  assert.deepEqual(parseHashRoute('#v0.1.0'), {
    view: 'changelog',
    targetVersion: 'v0.1.0',
    anchor: null,
  });
  assert.deepEqual(parseHashRoute('#main@3a1d37c'), {
    view: 'changelog',
    targetVersion: 'main@3a1d37c',
    anchor: null,
  });
});

test('filterChangelogVersions searches title, summary, and rawSections', () => {
  const syncedChangelogPath = resolve(__dirname, '../../public/CHANGELOG.md');
  const syncedMarkdown = readFileSync(syncedChangelogPath, 'utf8');
  const versions = parseChangelogMarkdown(syncedMarkdown);

  const resTitle = filterChangelogVersions(versions, '首个正式版本');
  assert.equal(resTitle.matchedVersionsCount, 1);
  assert.equal(resTitle.versions[0].version, 'v0.1.0');

  const resSummary = filterChangelogVersions(versions, '跨平台');
  assert.equal(resSummary.matchedVersionsCount, 1);
});
