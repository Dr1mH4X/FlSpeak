import React, { useMemo } from 'react';
import { LuArrowDown, LuChevronRight } from 'react-icons/lu';
import type { TranslationKey } from '../i18n/translations';
import type {
  ArchId,
  ClassifiedAsset,
  DetectedOs,
  PlatformId,
} from '../types/release';
import { findRecommendedAsset } from '../utils/detectDevice';
import {
  getPlatformLabelKey,
  PlatformIcon,
  PlatformPopup,
} from './PlatformPopup';
import { WorkspacePreview } from './WorkspacePreview';
import { FactsGrid } from './FactsGrid';

interface HeroProps {
  selectedPlatform: PlatformId;
  selectedArch: ArchId;
  detectedOs: DetectedOs;
  onSelectPlatform: (platform: PlatformId) => void;
  releaseTag: string | null;
  hasChangelog: boolean;
  classifiedAssets: ClassifiedAsset[];
  repoSlug?: string;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

const BRAND_CHARS = ['F', 'l', 'S', 'p', 'e', 'a', 'k'];

function getExpectedAssetFilename(
  platform: PlatformId,
  arch: ArchId,
  versionTag: string | null
): string {
  const ver = versionTag ? versionTag.replace(/^v/, '') : '0.1.0';
  const archTag = arch === 'arm64' ? 'arm64' : 'amd64';
  switch (platform) {
    case 'windows':
      return `flspeak-${ver}-windows-${archTag}.zip`;
    case 'macos':
      return `flspeak-${ver}-macos-${archTag}.zip`;
    case 'linux':
      return `flspeak-${ver}-linux-${archTag}.tar.gz`;
    case 'android':
      return `flspeak-${ver}-android-arm64-v8a.apk`;
  }
}

export const Hero: React.FC<HeroProps> = ({
  selectedPlatform,
  selectedArch,
  detectedOs,
  onSelectPlatform,
  releaseTag,
  hasChangelog,
  classifiedAssets,
  repoSlug = 'Dr1mH4X/FlSpeak',
  t,
}) => {
  const recommendedAsset = useMemo(() => {
    if (detectedOs === 'ios') return null;
    return findRecommendedAsset(
      classifiedAssets,
      selectedPlatform,
      selectedArch
    );
  }, [classifiedAssets, detectedOs, selectedPlatform, selectedArch]);

  const platformLabel = t(getPlatformLabelKey(selectedPlatform));

  const directDownloadUrl = useMemo(() => {
    if (recommendedAsset) {
      return recommendedAsset.downloadUrl;
    }
    const filename = getExpectedAssetFilename(
      selectedPlatform,
      selectedArch,
      releaseTag
    );
    return `https://github.com/${repoSlug}/releases/latest/download/${filename}`;
  }, [recommendedAsset, selectedPlatform, selectedArch, releaseTag, repoSlug]);

  const ctaSubtitle = useMemo(() => {
    if (recommendedAsset) {
      const archLabel =
        recommendedAsset.platform === 'macos'
          ? recommendedAsset.macChip === 'intel'
            ? t('chipIntel')
            : recommendedAsset.macChip === 'universal'
              ? t('chipUniversal')
              : t('chipAppleSilicon')
          : recommendedAsset.arch === 'arm64'
            ? 'ARM64'
            : 'x64';
      return `${archLabel} · ${recommendedAsset.sizeFormatted}`;
    }
    const archLabel =
      selectedPlatform === 'macos'
        ? selectedArch === 'arm64'
          ? t('chipAppleSilicon')
          : t('chipIntel')
        : selectedArch === 'arm64'
          ? 'ARM64'
          : 'x64';
    return archLabel;
  }, [recommendedAsset, selectedPlatform, selectedArch, t]);

  const displayTag = releaseTag || 'v0.1.0';

  return (
    <section className="hero-section">
      <div className="hero-header-stack">
        {(releaseTag || hasChangelog) && (
          <a href="#latest-release" className="hero-eyebrow-pill">
            <span className="eyebrow-pulse-dot" aria-hidden="true" />
            <span>{t('eyebrowReleased', { tag: displayTag })}</span>
            <LuChevronRight size={13} strokeWidth={2} aria-hidden="true" />
          </a>
        )}

        <h1 className="hero-display-title">
          <span className="hero-brand-line" aria-label={t('appTitle')}>
            {BRAND_CHARS.map((ch, idx) => (
              <span
                key={idx}
                className="hero-brand-char"
                style={{ '--char-idx': idx } as React.CSSProperties}
                aria-hidden="true"
              >
                {ch}
              </span>
            ))}
          </span>

          <span className="hero-platform-line">
            <span className="hero-for-word">{t('heroTitlePrefix')}</span>
            <PlatformPopup
              selectedPlatform={selectedPlatform}
              onSelectPlatform={onSelectPlatform}
              t={t}
            />
          </span>
        </h1>

        <p className="hero-lede">{t('heroLede')}</p>

        <div className="hero-cta-wrap">
          <a
            href={directDownloadUrl}
            className="hero-primary-cta"
          >
            <span className="hero-cta-icon" aria-hidden="true">
              <PlatformIcon platform={selectedPlatform} size={22} />
            </span>

            <span className="hero-cta-copy">
              <span className="hero-cta-main">
                {t('ctaDownloadFor', { platform: platformLabel })}
              </span>
              <span className="hero-cta-sub">{ctaSubtitle}</span>
            </span>

            <span className="hero-cta-arrow" aria-hidden="true">
              <LuArrowDown size={18} strokeWidth={2} />
            </span>
          </a>

          {detectedOs === 'ios' && (
            <p className="hero-device-notice">{t('heroIosNotice')}</p>
          )}
        </div>
      </div>

      <WorkspacePreview />

      <FactsGrid t={t} />
    </section>
  );
};
