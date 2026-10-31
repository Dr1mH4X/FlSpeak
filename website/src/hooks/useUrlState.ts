import { useEffect } from 'react';
import type { ArchId, PlatformId } from '../types/release';

const VALID_PLATFORMS: PlatformId[] = ['windows', 'macos', 'linux', 'android'];
const VALID_ARCHS: ArchId[] = ['x64', 'arm64'];

interface UrlStateCallbacks {
  onPlatformParam: (platform: PlatformId) => void;
  onArchParam: (arch: ArchId) => void;
  onQueryParam: (query: string) => void;
  onVersionHash: (hashTarget: string) => void;
}

export function useUrlState({
  onPlatformParam,
  onArchParam,
  onQueryParam,
  onVersionHash,
}: UrlStateCallbacks) {
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const url = new URL(window.location.href);
    const platformRaw = (url.searchParams.get('platform') || '').toLowerCase();
    const archRaw = (url.searchParams.get('arch') || '').toLowerCase();
    const queryRaw = url.searchParams.get('q');
    const hashRaw = window.location.hash ? window.location.hash.slice(1) : '';

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

    if (
      hashRaw &&
      hashRaw !== 'download' &&
      hashRaw !== 'changelog' &&
      hashRaw !== 'workspace'
    ) {
      onVersionHash(decodeURIComponent(hashRaw));
    }

    const handleHashChange = () => {
      const nextHash = window.location.hash
        ? window.location.hash.slice(1)
        : '';
      if (
        nextHash &&
        nextHash !== 'download' &&
        nextHash !== 'changelog' &&
        nextHash !== 'workspace'
      ) {
        onVersionHash(decodeURIComponent(nextHash));
      }
    };

    window.addEventListener('hashchange', handleHashChange);
    return () => window.removeEventListener('hashchange', handleHashChange);
  }, [onPlatformParam, onArchParam, onQueryParam, onVersionHash]);
}
