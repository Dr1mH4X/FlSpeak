import { useEffect } from 'react';
import type { ArchId, PlatformId } from '../types/release';

const VALID_PLATFORMS: PlatformId[] = ['windows', 'macos', 'linux', 'android'];
const VALID_ARCHS: ArchId[] = ['x64', 'arm64'];

export type SiteView = 'home' | 'changelog';

export function parseHashRoute(hashStr: string): {
  view: SiteView;
  targetVersion: string | null;
  anchor: string | null;
} {
  const raw = hashStr.replace(/^#/, '').trim();
  if (!raw || raw === '/' || raw === 'home') {
    return { view: 'home', targetVersion: null, anchor: null };
  }

  if (raw === 'download' || raw === 'workspace') {
    return { view: 'home', targetVersion: null, anchor: raw };
  }

  if (
    raw === 'changelog' ||
    raw.startsWith('/changelog') ||
    raw.startsWith('changelog')
  ) {
    let targetVersion: string | null = null;
    const qIndex = raw.indexOf('?');
    if (qIndex !== -1) {
      const search = new URLSearchParams(raw.slice(qIndex + 1));
      const v = search.get('v') || search.get('version');
      if (v) targetVersion = decodeURIComponent(v);
    }
    if (!targetVersion) {
      const subParts = raw.split(/[/#]/).filter(Boolean);
      if (subParts.length > 1 && subParts[0] === 'changelog') {
        targetVersion = decodeURIComponent(subParts[1]);
      }
    }
    return { view: 'changelog', targetVersion, anchor: null };
  }

  if (/^v?\d+\.\d+/i.test(raw) || /^main@/i.test(raw)) {
    return {
      view: 'changelog',
      targetVersion: decodeURIComponent(raw),
      anchor: null,
    };
  }

  return { view: 'home', targetVersion: null, anchor: raw };
}

interface UrlStateCallbacks {
  onPlatformParam: (platform: PlatformId) => void;
  onArchParam: (arch: ArchId) => void;
  onQueryParam: (query: string) => void;
  onVersionHash: (hashTarget: string) => void;
  onViewChange: (view: SiteView) => void;
}

export function useUrlState({
  onPlatformParam,
  onArchParam,
  onQueryParam,
  onVersionHash,
  onViewChange,
}: UrlStateCallbacks) {
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const url = new URL(window.location.href);
    const platformRaw = (url.searchParams.get('platform') || '').toLowerCase();
    const archRaw = (url.searchParams.get('arch') || '').toLowerCase();
    const queryRaw = url.searchParams.get('q');
    const hashRaw = window.location.hash || '';

    let hadSearchParams = false;

    if (VALID_PLATFORMS.includes(platformRaw as PlatformId)) {
      onPlatformParam(platformRaw as PlatformId);
      hadSearchParams = true;
    }

    if (VALID_ARCHS.includes(archRaw as ArchId)) {
      onArchParam(archRaw as ArchId);
      hadSearchParams = true;
    }

    if (queryRaw !== null && queryRaw.trim().length > 0) {
      onQueryParam(queryRaw.trim());
      hadSearchParams = true;
    }

    if (hadSearchParams) {
      const cleanUrl = `${window.location.pathname}${window.location.hash}`;
      window.history.replaceState(null, '', cleanUrl);
    }

    const initialRoute = parseHashRoute(hashRaw);
    onViewChange(initialRoute.view);
    if (initialRoute.targetVersion) {
      onVersionHash(initialRoute.targetVersion);
    } else if (initialRoute.anchor) {
      requestAnimationFrame(() => {
        const el = document.getElementById(initialRoute.anchor!);
        if (el) el.scrollIntoView({ behavior: 'smooth' });
      });
    }

    const handleHashChange = () => {
      const nextRoute = parseHashRoute(window.location.hash || '');
      onViewChange(nextRoute.view);
      if (nextRoute.targetVersion) {
        onVersionHash(nextRoute.targetVersion);
      } else if (nextRoute.anchor) {
        requestAnimationFrame(() => {
          const el = document.getElementById(nextRoute.anchor!);
          if (el) el.scrollIntoView({ behavior: 'smooth' });
        });
      }
    };

    window.addEventListener('hashchange', handleHashChange);
    return () => window.removeEventListener('hashchange', handleHashChange);
  }, [
    onPlatformParam,
    onArchParam,
    onQueryParam,
    onVersionHash,
    onViewChange,
  ]);
}
