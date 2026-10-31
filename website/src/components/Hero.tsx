import React, { useMemo, useRef, useState } from 'react';
import type { Locale, TranslationKey } from '../i18n/translations';
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
  locale: Locale;
  selectedPlatform: PlatformId;
  selectedArch: ArchId;
  detectedOs: DetectedOs;
  onSelectPlatform: (platform: PlatformId) => void;
  releaseTag: string | null;
  hasChangelog: boolean;
  classifiedAssets: ClassifiedAsset[];
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

const BRAND_CHARS = ['F', 'l', 'S', 'p', 'e', 'a', 'k'];

function getCtaKindSubtitleKey(
  kindKey: ClassifiedAsset['kindKey']
): TranslationKey {
  switch (kindKey) {
    case 'installer':
      return 'ctaSubInstaller';
    case 'portable':
      return 'ctaSubPortable';
    case 'dmg':
      return 'ctaSubDmg';
    case 'appArchive':
      return 'ctaSubArchive';
    case 'deb':
      return 'ctaSubDeb';
    case 'rpm':
      return 'ctaSubRpm';
    case 'appimage':
      return 'ctaSubAppImage';
    case 'tarball':
      return 'ctaSubPortable';
    case 'apkArm64':
    case 'apkArmv7':
    case 'apkX64':
    case 'apkUniversal':
      return 'ctaSubApk';
  }
}

export const Hero: React.FC<HeroProps> = ({
  locale,
  selectedPlatform,
  selectedArch,
  detectedOs,
  onSelectPlatform,
  releaseTag,
  hasChangelog,
  classifiedAssets,
  t,
}) => {
  const ctaRef = useRef<HTMLAnchorElement | null>(null);
  const [magnetOffset, setMagnetOffset] = useState<{ x: number; y: number }>({
    x: 0,
    y: 0,
  });

  const recommendedAsset = useMemo(() => {
    if (detectedOs === 'ios') return null;
    return findRecommendedAsset(
      classifiedAssets,
      selectedPlatform,
      selectedArch
    );
  }, [classifiedAssets, detectedOs, selectedPlatform, selectedArch]);

  const platformLabel = t(getPlatformLabelKey(selectedPlatform));

  const ctaSubtitle = useMemo(() => {
    if (!recommendedAsset) {
      return t('ctaSubSourceNote');
    }
    const kindLabel = t(getCtaKindSubtitleKey(recommendedAsset.kindKey));
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
    return `${archLabel} · ${kindLabel} · ${recommendedAsset.sizeFormatted}`;
  }, [recommendedAsset, t]);

  const handleCtaPointerMove = (e: React.PointerEvent<HTMLAnchorElement>) => {
    const el = ctaRef.current;
    if (!el) return;
    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) return;

    const rect = el.getBoundingClientRect();
    const relX = (e.clientX - (rect.left + rect.width / 2)) / (rect.width / 2);
    const relY = (e.clientY - (rect.top + rect.height / 2)) / (rect.height / 2);
    setMagnetOffset({
      x: Math.max(-5, Math.min(5, relX * 4.5)),
      y: Math.max(-3, Math.min(3, relY * 2.8)),
    });
  };

  const handleCtaPointerLeave = () => {
    setMagnetOffset({ x: 0, y: 0 });
  };

  return (
    <section className="hero-section">
      <div className="hero-header-stack">
        {(releaseTag || hasChangelog) && (
          <a href="#changelog" className="hero-eyebrow-pill">
            <span className="eyebrow-pulse-dot" aria-hidden="true" />
            <span>
              {releaseTag
                ? t('eyebrowReleased', { tag: releaseTag })
                : t('eyebrowCommits')}
            </span>
            <svg
              viewBox="0 0 16 16"
              width="13"
              height="13"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <path d="M6 3.5L10.5 8 6 12.5" />
            </svg>
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
            ref={ctaRef}
            href={recommendedAsset ? recommendedAsset.downloadUrl : '#download'}
            className="hero-primary-cta"
            style={{
              transform: `translate3d(${magnetOffset.x.toFixed(2)}px, ${magnetOffset.y.toFixed(2)}px, 0)`,
            }}
            onPointerMove={handleCtaPointerMove}
            onPointerLeave={handleCtaPointerLeave}
          >
            <span className="hero-cta-icon" aria-hidden="true">
              {recommendedAsset ? (
                <PlatformIcon platform={selectedPlatform} size={22} />
              ) : (
                <svg
                  viewBox="0 0 24 24"
                  width="21"
                  height="21"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2.1"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3" />
                </svg>
              )}
            </span>

            <span className="hero-cta-copy">
              <span className="hero-cta-main">
                {recommendedAsset
                  ? t('ctaDownloadFor', { platform: platformLabel })
                  : t('ctaChooseBuild')}
              </span>
              <span className="hero-cta-sub">{ctaSubtitle}</span>
            </span>

            <span className="hero-cta-arrow" aria-hidden="true">
              <svg
                viewBox="0 0 20 20"
                width="18"
                height="18"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M10 4v11M5.5 10.5L10 15l4.5-4.5" />
              </svg>
            </span>
          </a>

          {detectedOs === 'ios' && (
            <p className="hero-device-notice">{t('heroIosNotice')}</p>
          )}
        </div>
      </div>

      <WorkspacePreview locale={locale} t={t} />

      <FactsGrid t={t} />
    </section>
  );
};
