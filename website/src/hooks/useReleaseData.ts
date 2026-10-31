import { useEffect, useMemo, useState } from 'react';
import type {
  ChangelogVersion,
  ClassifiedAsset,
  RawReleaseAsset,
  ReleaseManifest,
} from '../types/release';
import { classifyAllAssets } from '../utils/detectDevice';
import {
  buildChangelogFromCommits,
  parseChangelogMarkdown,
  type RawCommitInput,
} from '../utils/parseChangelog';

const DEFAULT_REPO = 'Dr1mH4X/FlSpeak';
const CACHE_KEY = 'flspeak.release.cache.v1';
const CACHE_TTL_MS = 15 * 60 * 1000;

interface CachedReleasePayload {
  timestamp: number;
  manifest: ReleaseManifest;
  changelogMarkdown: string;
  FallbackCommits?: RawCommitInput[];
}

const EMPTY_MANIFEST: ReleaseManifest = {
  repo: DEFAULT_REPO,
  tag: null,
  name: null,
  publishedAt: null,
  htmlUrl: `https://github.com/${DEFAULT_REPO}/releases`,
  stars: null,
  sha256SumsUrl: null,
  assets: [],
};

function readLocalCache(): CachedReleasePayload | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CachedReleasePayload;
    if (
      parsed &&
      typeof parsed.timestamp === 'number' &&
      Date.now() - parsed.timestamp < CACHE_TTL_MS &&
      parsed.manifest
    ) {
      return parsed;
    }
  } catch {
    // Ignore invalid cache
  }
  return null;
}

function writeLocalCache(payload: CachedReleasePayload) {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(payload));
  } catch {
    // Ignore storage quota errors
  }
}

async function fetchLiveGithubFallback(repoSlug: string): Promise<{
  manifest: ReleaseManifest;
  commits: RawCommitInput[];
}> {
  const headers: HeadersInit = {
    Accept: 'application/vnd.github+json',
  };

  const [repoRes, releasesRes, commitsRes] = await Promise.allSettled([
    fetch(`https://api.github.com/repos/${repoSlug}`, { headers }),
    fetch(`https://api.github.com/repos/${repoSlug}/releases?per_page=10`, {
      headers,
    }),
    fetch(`https://api.github.com/repos/${repoSlug}/commits?per_page=100`, {
      headers,
    }),
  ]);

  let stars: number | null = null;
  if (repoRes.status === 'fulfilled' && repoRes.value.ok) {
    const repoData = (await repoRes.value.json()) as {
      stargazers_count?: number;
    };
    if (typeof repoData.stargazers_count === 'number') {
      stars = repoData.stargazers_count;
    }
  }

  let manifest: ReleaseManifest = {
    ...EMPTY_MANIFEST,
    repo: repoSlug,
    stars,
  };

  if (releasesRes.status === 'fulfilled' && releasesRes.value.ok) {
    const releases = (await releasesRes.value.json()) as Array<{
      draft?: boolean;
      prerelease?: boolean;
      tag_name?: string;
      name?: string;
      published_at?: string;
      created_at?: string;
      html_url?: string;
      assets?: Array<{
        name: string;
        size: number;
        browser_download_url: string;
        content_type?: string;
        digest?: string;
      }>;
    }>;

    if (Array.isArray(releases) && releases.length > 0) {
      const chosen =
        releases.find((r) => !r.draft && !r.prerelease) ||
        releases.find((r) => !r.draft) ||
        releases[0];

      if (chosen) {
        const rawAssets: RawReleaseAsset[] = [];
        let sha256SumsUrl: string | null = null;

        for (const a of chosen.assets || []) {
          if (/sha256sums/i.test(a.name)) {
            sha256SumsUrl = a.browser_download_url;
          }
          let sha256: string | null = null;
          if (typeof a.digest === 'string' && a.digest.startsWith('sha256:')) {
            sha256 = a.digest.slice('sha256:'.length);
          }
          rawAssets.push({
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
          assets: rawAssets,
        };
      }
    }
  }

  const commits: RawCommitInput[] = [];
  if (commitsRes.status === 'fulfilled' && commitsRes.value.ok) {
    const rawCommits = (await commitsRes.value.json()) as Array<{
      sha?: string;
      commit?: {
        message?: string;
        committer?: { date?: string };
        author?: { date?: string };
      };
    }>;
    if (Array.isArray(rawCommits)) {
      for (const item of rawCommits) {
        if (!item?.sha || !item?.commit?.message) continue;
        const date =
          item.commit.committer?.date || item.commit.author?.date || '';
        commits.push({
          sha: item.sha,
          date: date.slice(0, 10),
          message: item.commit.message,
        });
      }
    }
  }

  return { manifest, commits };
}

export function useReleaseData() {
  const [manifest, setManifest] = useState<ReleaseManifest>(EMPTY_MANIFEST);
  const [changelogVersions, setChangelogVersions] = useState<
    ChangelogVersion[]
  >([]);
  const [loading, setLoading] = useState<boolean>(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setLoading(true);
      let loadedManifest: ReleaseManifest | null = null;
      let loadedMarkdown = '';

      const [relRes, logRes] = await Promise.allSettled([
        fetch('./release.json', { cache: 'no-cache' }),
        fetch('./CHANGELOG.md', { cache: 'no-cache' }),
      ]);

      if (relRes.status === 'fulfilled' && relRes.value.ok) {
        try {
          const json = (await relRes.value.json()) as ReleaseManifest;
          if (json && typeof json.repo === 'string') {
            loadedManifest = json;
          }
        } catch {
          // Invalid static JSON
        }
      }

      if (logRes.status === 'fulfilled' && logRes.value.ok) {
        try {
          const text = await logRes.value.text();
          if (text && !text.trim().startsWith('<!DOCTYPE html')) {
            loadedMarkdown = text;
          }
        } catch {
          // Invalid static markdown
        }
      }

      const repoSlug = loadedManifest?.repo || DEFAULT_REPO;
      let parsedVersions = parseChangelogMarkdown(loadedMarkdown, repoSlug);

      if (!loadedManifest || parsedVersions.length === 0) {
        const cached = readLocalCache();
        if (cached) {
          if (!loadedManifest) loadedManifest = cached.manifest;
          if (parsedVersions.length === 0) {
            if (cached.changelogMarkdown) {
              parsedVersions = parseChangelogMarkdown(
                cached.changelogMarkdown,
                repoSlug
              );
            } else if (cached.FallbackCommits) {
              parsedVersions = buildChangelogFromCommits(
                cached.FallbackCommits,
                repoSlug
              );
            }
          }
        } else {
          try {
            const live = await fetchLiveGithubFallback(repoSlug);
            if (!loadedManifest) {
              loadedManifest = live.manifest;
            } else if (
              loadedManifest.stars === null &&
              live.manifest.stars !== null
            ) {
              loadedManifest = {
                ...loadedManifest,
                stars: live.manifest.stars,
              };
            }
            if (parsedVersions.length === 0 && live.commits.length > 0) {
              parsedVersions = buildChangelogFromCommits(
                live.commits,
                repoSlug
              );
            }
            writeLocalCache({
              timestamp: Date.now(),
              manifest: loadedManifest || live.manifest,
              changelogMarkdown: loadedMarkdown,
              FallbackCommits: live.commits,
            });
          } catch {
            // Network error, keep honest empty state
          }
        }
      }

      if (!cancelled) {
        setManifest(loadedManifest || EMPTY_MANIFEST);
        setChangelogVersions(parsedVersions);
        setLoading(false);
      }
    }

    load();
    return () => {
      cancelled = true;
    };
  }, []);

  const classifiedAssets: ClassifiedAsset[] = useMemo(
    () => classifyAllAssets(manifest.assets),
    [manifest.assets]
  );

  return {
    manifest,
    classifiedAssets,
    changelogVersions,
    loading,
  };
}
