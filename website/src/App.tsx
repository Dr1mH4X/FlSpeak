import React, { useCallback, useEffect, useRef, useState } from 'react';
import { AmbientBackground } from './components/AmbientBackground';
import { ChangelogSection } from './components/ChangelogSection';
import { Footer } from './components/Footer';
import { Hero } from './components/Hero';
import { Navbar } from './components/Navbar';
import { useI18n } from './hooks/useI18n';
import { useReleaseData } from './hooks/useReleaseData';
import { useTheme } from './hooks/useTheme';
import { useUrlState } from './hooks/useUrlState';
import type { ArchId, DetectedOs, PlatformId } from './types/release';
import { detectDevice } from './utils/detectDevice';

export const App: React.FC = () => {
  const { theme, toggleTheme } = useTheme();
  const { locale, toggleLocale, t, formatDate, formatRelativeTime } = useI18n();
  const { manifest, classifiedAssets, changelogVersions } = useReleaseData();

  const [selectedPlatform, setSelectedPlatform] =
    useState<PlatformId>('windows');
  const [selectedArch, setSelectedArch] = useState<ArchId>('x64');
  const [detectedOs, setDetectedOs] = useState<DetectedOs>('windows');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [targetVersionHash, setTargetVersionHash] = useState<string | null>(
    null
  );

  // Track if URL explicitly set platform or arch so async device detection doesn't overwrite it
  const urlOverrodePlatformRef = useRef(false);
  const urlOverrodeArchRef = useRef(false);

  const handlePlatformParam = useCallback((plat: PlatformId) => {
    urlOverrodePlatformRef.current = true;
    setSelectedPlatform(plat);
  }, []);

  const handleArchParam = useCallback((arch: ArchId) => {
    urlOverrodeArchRef.current = true;
    setSelectedArch(arch);
  }, []);

  const handleQueryParam = useCallback((q: string) => {
    setSearchQuery(q);
  }, []);

  const handleVersionHash = useCallback((hashTarget: string) => {
    setTargetVersionHash(hashTarget);
  }, []);

  useUrlState({
    onPlatformParam: handlePlatformParam,
    onArchParam: handleArchParam,
    onQueryParam: handleQueryParam,
    onVersionHash: handleVersionHash,
  });

  useEffect(() => {
    let cancelled = false;
    detectDevice()
      .then((info) => {
        if (cancelled) return;
        setDetectedOs(info.os);
        if (!urlOverrodePlatformRef.current) {
          setSelectedPlatform(info.platform);
        }
        if (!urlOverrodeArchRef.current) {
          setSelectedArch(info.arch);
        }
      })
      .catch(() => {
        // Keep safe defaults
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const handleSelectPlatform = useCallback((plat: PlatformId) => {
    urlOverrodePlatformRef.current = true;
    setSelectedPlatform(plat);
  }, []);

  const handleTargetVersionHandled = useCallback(() => {
    setTargetVersionHash(null);
  }, []);

  const repoSlug = manifest.repo || 'Dr1mH4X/FlSpeak';
  const repoUrl = `https://github.com/${repoSlug}`;

  return (
    <div className="app-root">
      <AmbientBackground />

      <Navbar
        locale={locale}
        onToggleLocale={toggleLocale}
        theme={theme}
        onToggleTheme={toggleTheme}
        stars={manifest.stars}
        repoUrl={repoUrl}
        t={t}
      />

      <main className="page-container">
        <Hero
          selectedPlatform={selectedPlatform}
          selectedArch={selectedArch}
          detectedOs={detectedOs}
          onSelectPlatform={handleSelectPlatform}
          releaseTag={manifest.tag}
          hasChangelog={changelogVersions.length > 0}
          classifiedAssets={classifiedAssets}
          repoSlug={repoSlug}
          t={t}
        />

        <ChangelogSection
          versions={changelogVersions}
          repoSlug={repoSlug}
          searchQuery={searchQuery}
          onSearchQueryChange={setSearchQuery}
          targetVersionHash={targetVersionHash}
          onTargetVersionHandled={handleTargetVersionHandled}
          formatDate={formatDate}
          formatRelativeTime={formatRelativeTime}
          t={t}
        />
      </main>

      <Footer repoSlug={repoSlug} t={t} />
    </div>
  );
};

export default App;
