import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { TranslationKey } from '../i18n/translations';
import type {
  ArchId,
  ClassifiedAsset,
  PlatformId,
  ReleaseManifest,
} from '../types/release';
import { getPlatformLabelKey, PlatformIcon } from './PlatformPopup';

interface DownloadSectionProps {
  manifest: ReleaseManifest;
  classifiedAssets: ClassifiedAsset[];
  selectedPlatform: PlatformId;
  selectedArch: ArchId;
  onSelectPlatform: (platform: PlatformId) => void;
  onSelectArch: (arch: ArchId) => void;
  formatDate: (iso: string | null | undefined) => string;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

const TAB_PLATFORMS: PlatformId[] = ['windows', 'macos', 'linux', 'android'];
const ARCH_OPTIONS: ArchId[] = ['x64', 'arm64'];

function getPlatformHintKey(platform: PlatformId): TranslationKey {
  switch (platform) {
    case 'windows':
      return 'downloadHintWindows';
    case 'macos':
      return 'downloadHintMacos';
    case 'linux':
      return 'downloadHintLinux';
    case 'android':
      return 'downloadHintAndroid';
  }
}

function getAssetTitleAndDesc(
  asset: ClassifiedAsset,
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string
): { title: string; desc: string } {
  const archText = asset.arch === 'arm64' ? 'ARM64' : 'x64';
  const chipText =
    asset.macChip === 'intel'
      ? t('chipIntel')
      : asset.macChip === 'universal'
        ? t('chipUniversal')
        : t('chipAppleSilicon');

  switch (asset.kindKey) {
    case 'installer':
      return {
        title: t('kindInstaller'),
        desc: t('kindInstallerDesc', { arch: archText }),
      };
    case 'portable':
      return {
        title: t('kindPortable'),
        desc: t('kindPortableDesc', { arch: archText }),
      };
    case 'dmg':
      return {
        title: t('kindDmg', { chip: chipText }),
        desc: t('kindDmgDesc'),
      };
    case 'appArchive':
      return {
        title: t('kindAppArchive', { chip: chipText }),
        desc: t('kindAppArchiveDesc'),
      };
    case 'deb':
      return {
        title: t('kindDeb'),
        desc: t('kindDebDesc', { arch: archText }),
      };
    case 'rpm':
      return {
        title: t('kindRpm'),
        desc: t('kindRpmDesc', { arch: archText }),
      };
    case 'appimage':
      return {
        title: t('kindAppimage'),
        desc: t('kindAppimageDesc', { arch: archText }),
      };
    case 'tarball':
      return {
        title: t('kindTarball'),
        desc: t('kindTarballDesc', { arch: archText }),
      };
    case 'apkArm64':
      return {
        title: t('kindApkArm64'),
        desc: t('kindApkArm64Desc'),
      };
    case 'apkArmv7':
      return {
        title: t('kindApkArmv7'),
        desc: t('kindApkArmv7Desc'),
      };
    case 'apkX64':
      return {
        title: t('kindApkX64'),
        desc: t('kindApkX64Desc'),
      };
    case 'apkUniversal':
      return {
        title: t('kindApkUniversal'),
        desc: t('kindApkUniversalDesc'),
      };
  }
}

function getPlatformExtraConfig(
  platform: PlatformId,
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string
): { title: string; note: string; command: string } {
  switch (platform) {
    case 'windows':
      return {
        title: t('extraWindowsTitle'),
        note: t('extraWindowsNote'),
        command: 'dart setup.dart windows x64 --version 0.1.0',
      };
    case 'macos':
      return {
        title: t('extraMacosTitle'),
        note: t('extraMacosNote'),
        command:
          'xattr -cr /Applications/FlSpeak.app && dart setup.dart macos arm64 --version 0.1.0',
      };
    case 'linux':
      return {
        title: t('extraLinuxTitle'),
        note: t('extraLinuxNote'),
        command:
          'sudo apt install -y libopus-dev libasound2-dev libsecret-1-dev && dart setup.dart linux x64 --version 0.1.0',
      };
    case 'android':
      return {
        title: t('extraAndroidTitle'),
        note: t('extraAndroidNote'),
        command:
          'dart setup.dart android arm64 --version 0.1.0 && adb install -r dist/FlSpeak-0.1.0-android-arm64.apk',
      };
  }
}

export const DownloadSection: React.FC<DownloadSectionProps> = ({
  manifest,
  classifiedAssets,
  selectedPlatform,
  selectedArch,
  onSelectPlatform,
  onSelectArch,
  formatDate,
  t,
}) => {
  const [jellyActive, setJellyActive] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const [pillRect, setPillRect] = useState<{ left: number; width: number }>({
    left: 0,
    width: 0,
  });

  // Measure active platform tab for sliding indicator
  useEffect(() => {
    const updatePill = () => {
      const idx = TAB_PLATFORMS.indexOf(selectedPlatform);
      const btn = tabRefs.current[idx];
      if (btn) {
        setPillRect({
          left: btn.offsetLeft,
          width: btn.offsetWidth,
        });
      }
    };
    updatePill();
    window.addEventListener('resize', updatePill, { passive: true });
    return () => window.removeEventListener('resize', updatePill);
  }, [selectedPlatform, t]);

  const handlePlatformSwitch = (plat: PlatformId) => {
    if (plat === selectedPlatform) return;
    setJellyActive(true);
    onSelectPlatform(plat);
    window.setTimeout(() => setJellyActive(false), 320);
  };

  const handleCopy = async (id: string, text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopiedId(id);
      window.setTimeout(() => {
        setCopiedId((prev) => (prev === id ? null : prev));
      }, 2000);
    } catch {
      // Clipboard API unavailable
    }
  };

  const showArchSelector =
    selectedPlatform === 'windows' || selectedPlatform === 'linux';

  const visibleAssets = useMemo(() => {
    const byPlatform = classifiedAssets.filter(
      (a) => a.platform === selectedPlatform
    );
    if (!showArchSelector) {
      return byPlatform;
    }
    return byPlatform.filter((a) => a.arch === selectedArch);
  }, [classifiedAssets, selectedPlatform, selectedArch, showArchSelector]);

  const platformCounts = useMemo(() => {
    const counts: Record<PlatformId, number> = {
      windows: 0,
      macos: 0,
      linux: 0,
      android: 0,
    };
    for (const a of classifiedAssets) {
      counts[a.platform] += 1;
    }
    return counts;
  }, [classifiedAssets]);

  const extraConfig = getPlatformExtraConfig(selectedPlatform, t);
  const platformLabel = t(getPlatformLabelKey(selectedPlatform));

  return (
    <section id="download" className="section-block download-section">
      <div className="section-two-col">
        {/* Left Sticky Info Rail */}
        <div className="section-left-rail">
          <div className="section-index-row">
            <span className="section-index-num">{t('downloadIndex')}</span>
            <span className="section-index-line" aria-hidden="true" />
          </div>

          <h2 className="section-heading">{t('downloadTitle')}</h2>

          <p className="section-meta-badge">
            {manifest.tag
              ? t('downloadVersionMeta', {
                  tag: manifest.tag,
                  date: formatDate(manifest.publishedAt),
                })
              : t('downloadNoVersionMeta')}
          </p>

          <p className="section-lead">{t('downloadLead')}</p>

          <div className="section-rail-links">
            {manifest.sha256SumsUrl && (
              <a
                href={manifest.sha256SumsUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="rail-ext-link"
              >
                <svg
                  viewBox="0 0 24 24"
                  width="15"
                  height="15"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
                </svg>
                <span>{t('downloadSha256Sums')}</span>
              </a>
            )}

            <a
              href={manifest.htmlUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="rail-ext-link"
            >
              <span>{t('downloadAllReleases')}</span>
              <svg
                viewBox="0 0 24 24"
                width="14"
                height="14"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <path d="M7 17L17 7M7 7h10v10" />
              </svg>
            </a>
          </div>
        </div>

        {/* Right Interactive Matrix */}
        <div className="section-right-panel">
          {/* Top Controls Bar: Segmented Platform Controller + Dynamic Arch Sub-Selector */}
          <div className="download-controls-bar">
            <div
              className="platform-segmented-control"
              role="tablist"
              aria-label={t('platformPopupTitle')}
            >
              <span
                className={`segmented-active-pill ${jellyActive ? 'is-jelly' : ''}`}
                aria-hidden="true"
                style={{
                  transform: `translate3d(${pillRect.left}px, 0, 0)`,
                  width: `${pillRect.width}px`,
                }}
              />
              {TAB_PLATFORMS.map((plat, idx) => {
                const isSelected = plat === selectedPlatform;
                const count = platformCounts[plat];
                return (
                  <button
                    key={plat}
                    ref={(el) => {
                      tabRefs.current[idx] = el;
                    }}
                    type="button"
                    role="tab"
                    aria-selected={isSelected}
                    className={`platform-seg-btn ${isSelected ? 'is-selected' : ''}`}
                    onClick={() => handlePlatformSwitch(plat)}
                  >
                    <PlatformIcon platform={plat} size={16} />
                    <span>{t(getPlatformLabelKey(plat))}</span>
                    {count > 0 && (
                      <span className="platform-seg-count">{count}</span>
                    )}
                  </button>
                );
              })}
            </div>

            {showArchSelector && (
              <div
                className="arch-segmented-control"
                role="radiogroup"
                aria-label="CPU Architecture"
              >
                {ARCH_OPTIONS.map((arch) => {
                  const isSelected = arch === selectedArch;
                  return (
                    <button
                      key={arch}
                      type="button"
                      role="radio"
                      aria-checked={isSelected}
                      className={`arch-seg-btn ${isSelected ? 'is-selected' : ''}`}
                      onClick={() => onSelectArch(arch)}
                    >
                      {arch === 'x64' ? t('archX64') : t('archArm64')}
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          {/* Platform Hint Banner */}
          <div className="platform-hint-banner">
            <span className="platform-hint-icon" aria-hidden="true">
              <PlatformIcon platform={selectedPlatform} size={17} />
            </span>
            <p className="platform-hint-text">
              {t(getPlatformHintKey(selectedPlatform))}
            </p>
          </div>

          {/* Asset Rows or Honest Empty State */}
          {visibleAssets.length > 0 ? (
            <div className="build-assets-list" role="list">
              {visibleAssets.map((asset) => {
                const { title, desc } = getAssetTitleAndDesc(asset, t);
                const shaCopyId = `sha-${asset.name}`;
                const isShaCopied = copiedId === shaCopyId;

                return (
                  <div
                    key={asset.name}
                    role="listitem"
                    className={`build-row ${asset.recommended ? 'is-recommended' : ''}`}
                  >
                    <div className="build-row-left">
                      <span className="build-format-badge">{asset.badge}</span>
                      <div className="build-row-copy">
                        <div className="build-row-title-line">
                          <span className="build-row-title">{title}</span>
                          {asset.recommended && (
                            <span className="build-recommended-pill">
                              {t('recommendedBadge')}
                            </span>
                          )}
                        </div>
                        <div className="build-row-desc">{desc}</div>
                        <div className="build-row-filename">{asset.name}</div>
                      </div>
                    </div>

                    <div className="build-row-actions">
                      <span className="build-row-size">
                        {asset.sizeFormatted}
                      </span>

                      {asset.sha256 && (
                        <button
                          type="button"
                          className={`build-sha-btn ${isShaCopied ? 'is-copied' : ''}`}
                          onClick={() =>
                            handleCopy(shaCopyId, asset.sha256 || '')
                          }
                          aria-label={`${t('copySha256')} ${asset.name}`}
                        >
                          <span className="copy-icon-stack" aria-hidden="true">
                            <svg
                              viewBox="0 0 24 24"
                              width="14"
                              height="14"
                              fill="none"
                              stroke="currentColor"
                              strokeWidth="2"
                              className="icon-copy-default"
                            >
                              <rect
                                x="9"
                                y="9"
                                width="13"
                                height="13"
                                rx="2"
                              />
                              <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                            </svg>
                            <svg
                              viewBox="0 0 24 24"
                              width="14"
                              height="14"
                              fill="none"
                              stroke="currentColor"
                              strokeWidth="2.4"
                              className="icon-copy-check"
                            >
                              <polyline points="20 6 9 17 4 12" />
                            </svg>
                          </span>
                          <span>
                            {isShaCopied ? t('copiedSha256') : t('copySha256')}
                          </span>
                        </button>
                      )}

                      <a
                        href={asset.downloadUrl}
                        className="build-download-btn"
                        aria-label={t('downloadAssetAria', {
                          name: asset.name,
                        })}
                      >
                        <svg
                          viewBox="0 0 24 24"
                          width="16"
                          height="16"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2.1"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3" />
                        </svg>
                        <span>{asset.badge}</span>
                      </a>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="build-empty-state">
              <div className="build-empty-icon" aria-hidden="true">
                <PlatformIcon platform={selectedPlatform} size={26} />
              </div>
              <h3 className="build-empty-title">
                {t('emptyAssetsTitle', {
                  platform: showArchSelector
                    ? `${platformLabel} (${selectedArch === 'arm64' ? 'ARM64' : 'x64'})`
                    : platformLabel,
                })}
              </h3>
              <p className="build-empty-body">{t('emptyAssetsBody')}</p>
              <a
                href={manifest.htmlUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="build-empty-link"
              >
                <span>{t('emptyAssetsLink')}</span>
                <svg
                  viewBox="0 0 20 20"
                  width="15"
                  height="15"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M6 14L14 6M6 6h8v8" />
                </svg>
              </a>
            </div>
          )}

          {/* Platform Extras & CLI Build / Helper Block */}
          <div className="platform-extra-card">
            <div className="platform-extra-header">
              <div>
                <h3 className="platform-extra-title">{extraConfig.title}</h3>
                <p className="platform-extra-note">{extraConfig.note}</p>
              </div>
              <button
                type="button"
                className={`cli-copy-btn ${copiedId === `cli-${selectedPlatform}` ? 'is-copied' : ''}`}
                onClick={() =>
                  handleCopy(`cli-${selectedPlatform}`, extraConfig.command)
                }
                aria-label={t('copyCli')}
              >
                <span className="copy-icon-stack" aria-hidden="true">
                  <svg
                    viewBox="0 0 24 24"
                    width="15"
                    height="15"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    className="icon-copy-default"
                  >
                    <rect x="9" y="9" width="13" height="13" rx="2" />
                    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                  </svg>
                  <svg
                    viewBox="0 0 24 24"
                    width="15"
                    height="15"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.4"
                    className="icon-copy-check"
                  >
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </span>
                <span>
                  {copiedId === `cli-${selectedPlatform}`
                    ? t('copiedCli')
                    : t('copyCli')}
                </span>
              </button>
            </div>

            <pre className="platform-cli-pre">
              <code>
                <span className="cli-prompt" aria-hidden="true">
                  ${' '}
                </span>
                {extraConfig.command}
              </code>
            </pre>
          </div>
        </div>
      </div>
    </section>
  );
};
