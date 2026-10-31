import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { TranslationKey } from '../i18n/translations';
import type { ChangelogVersion } from '../types/release';
import {
  filterChangelogVersions,
  normalizeAnchorId,
} from '../utils/parseChangelog';
import { VersionNode } from './VersionNode';

interface ChangelogSectionProps {
  versions: ChangelogVersion[];
  repoSlug: string;
  searchQuery: string;
  onSearchQueryChange: (q: string) => void;
  targetVersionHash: string | null;
  onTargetVersionHandled: () => void;
  formatDate: (iso: string | null | undefined) => string;
  formatRelativeTime: (iso: string | null | undefined) => string;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

const INITIAL_VISIBLE_COUNT = 8;
const PAGE_INCREMENT = 15;

export const ChangelogSection: React.FC<ChangelogSectionProps> = ({
  versions,
  repoSlug,
  searchQuery,
  onSearchQueryChange,
  targetVersionHash,
  onTargetVersionHandled,
  formatDate,
  formatRelativeTime,
  t,
}) => {
  const searchInputRef = useRef<HTMLInputElement | null>(null);
  const [debouncedQuery, setDebouncedQuery] = useState<string>(searchQuery);
  const [visibleCount, setVisibleCount] = useState<number>(
    INITIAL_VISIBLE_COUNT
  );
  const [activeAnchorId, setActiveAnchorId] = useState<string>('');

  // 80ms debounce for search query
  useEffect(() => {
    const timer = window.setTimeout(() => {
      setDebouncedQuery(searchQuery);
    }, 80);
    return () => window.clearTimeout(timer);
  }, [searchQuery]);

  // Global "/" shortcut to focus search input
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
      const active = document.activeElement;
      const tag = active?.tagName.toLowerCase();
      if (
        tag === 'input' ||
        tag === 'textarea' ||
        (active as HTMLElement | null)?.isContentEditable
      ) {
        return;
      }
      e.preventDefault();
      searchInputRef.current?.focus();
      searchInputRef.current?.select();
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  // Expand pagination & scroll when visiting a deep #v... or #main@... anchor
  useEffect(() => {
    if (!targetVersionHash || versions.length === 0) return;
    const normalizedTarget = normalizeAnchorId(targetVersionHash).toLowerCase();
    const targetIdx = versions.findIndex(
      (v) =>
        v.anchorId.toLowerCase() === normalizedTarget ||
        v.version.toLowerCase() === targetVersionHash.toLowerCase()
    );

    if (targetIdx !== -1) {
      if (targetIdx >= visibleCount) {
        setVisibleCount(targetIdx + 2);
      }
      const targetAnchorId = versions[targetIdx].anchorId;
      setActiveAnchorId(targetAnchorId);
      requestAnimationFrame(() => {
        const el = document.getElementById(targetAnchorId);
        if (el) {
          el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
        onTargetVersionHandled();
      });
    } else {
      onTargetVersionHandled();
    }
  }, [targetVersionHash, versions, visibleCount, onTargetVersionHandled]);

  const filteredResult = useMemo(
    () => filterChangelogVersions(versions, debouncedQuery),
    [versions, debouncedQuery]
  );

  const isSearching = debouncedQuery.trim().length > 0;

  const displayedVersions = useMemo(() => {
    if (isSearching) {
      return filteredResult.versions;
    }
    return filteredResult.versions.slice(0, visibleCount);
  }, [filteredResult.versions, isSearching, visibleCount]);

  const remainingCount = Math.max(
    0,
    filteredResult.versions.length - displayedVersions.length
  );

  const earliestDate = useMemo(() => {
    if (versions.length === 0) return '';
    const last = versions[versions.length - 1];
    return formatDate(last.date);
  }, [versions, formatDate]);

  // Group all versions by year for TOC directory
  const tocGroups = useMemo(() => {
    const groups: Array<{
      year: string;
      items: Array<{
        anchorId: string;
        version: string;
        title?: string | null;
      }>;
    }> = [];

    for (const v of versions) {
      const year = v.year || (v.date ? v.date.slice(0, 4) : 'Other');
      let g = groups.find((grp) => grp.year === year);
      if (!g) {
        g = { year, items: [] };
        groups.push(g);
      }
      g.items.push({
        anchorId: v.anchorId,
        version: v.version,
        title: v.title,
      });
    }
    return groups;
  }, [versions]);

  // Track active version in viewport with IntersectionObserver
  useEffect(() => {
    if (typeof window === 'undefined' || !('IntersectionObserver' in window)) {
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setActiveAnchorId(entry.target.id);
            break;
          }
        }
      },
      {
        rootMargin: '-80px 0px -65% 0px',
        threshold: 0,
      }
    );

    const elements = document.querySelectorAll('.cl-version-node');
    elements.forEach((el) => observer.observe(el));

    return () => observer.disconnect();
  }, [displayedVersions]);

  const handleTocClick = (anchorId: string) => {
    const targetIdx = versions.findIndex((v) => v.anchorId === anchorId);
    if (targetIdx !== -1 && targetIdx >= visibleCount) {
      setVisibleCount(targetIdx + 2);
    }
    setActiveAnchorId(anchorId);
    requestAnimationFrame(() => {
      const el = document.getElementById(anchorId);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  };

  return (
    <section id="changelog" className="section-block changelog-section is-archive-page">
      {/* Back to Home Breadcrumb Header */}
      <div className="cl-top-nav-bar">
        <a href="#/" className="cl-back-home-btn">
          <svg
            viewBox="0 0 20 20"
            width="16"
            height="16"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <path d="M15 10H5M10 15l-5-5 5-5" />
          </svg>
          <span>{t('changelogBackToHome')}</span>
        </a>
      </div>

      <div className="section-two-col">
        {/* Left Sticky TOC & Search Rail */}
        <div className="section-left-rail is-sticky-rail">
          <h1 className="section-heading">{t('changelogAllReleasesTitle')}</h1>

          <p className="section-meta-badge">
            {versions.length > 0 && earliestDate
              ? t('changelogStats', {
                  count: versions.length,
                  since: earliestDate,
                })
              : t('changelogNoStats')}
          </p>

          <p className="section-lead">
            {t('changelogAllReleasesSubtitle')}
          </p>

          {/* Search Box */}
          <div className="cl-search-box">
            <span className="cl-search-icon" aria-hidden="true">
              <svg
                viewBox="0 0 20 20"
                width="16"
                height="16"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
              >
                <circle cx="8.5" cy="8.5" r="5.5" />
                <path d="M13 13l4 4" />
              </svg>
            </span>

            <input
              ref={searchInputRef}
              type="search"
              value={searchQuery}
              onChange={(e) => onSearchQueryChange(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Escape') {
                  e.preventDefault();
                  onSearchQueryChange('');
                  searchInputRef.current?.blur();
                }
              }}
              placeholder={t('changelogSearchPlaceholder')}
              aria-label={t('changelogSearchPlaceholder')}
              className="cl-search-input"
            />

            {searchQuery.length > 0 ? (
              <button
                type="button"
                className="cl-search-clear-btn"
                onClick={() => {
                  onSearchQueryChange('');
                  searchInputRef.current?.focus();
                }}
                aria-label={t('changelogClearSearch')}
              >
                <svg
                  viewBox="0 0 16 16"
                  width="13"
                  height="13"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                >
                  <path d="M4 4l8 8M12 4l-8 8" />
                </svg>
              </button>
            ) : (
              <kbd className="cl-search-kbd" aria-hidden="true">
                /
              </kbd>
            )}
          </div>

          {isSearching && (
            <div className="cl-search-stats" role="status">
              {filteredResult.matchedItemsCount > 0
                ? t('changelogSearchStats', {
                    matches: filteredResult.matchedItemsCount,
                    versions: filteredResult.matchedVersionsCount,
                  })
                : t('changelogSearchNoMatch', {
                    query: debouncedQuery.trim(),
                  })}
            </div>
          )}

          {/* TOC Navigation Tree */}
          {!isSearching && tocGroups.length > 0 && (
            <nav className="cl-toc-nav" aria-label={t('changelogTocTitle')}>
              <h2 className="cl-toc-heading">{t('changelogTocTitle')}</h2>
              <div className="cl-toc-groups">
                {tocGroups.map((group) => (
                  <div key={group.year} className="cl-toc-group">
                    <span className="cl-toc-year">{group.year}</span>
                    <ul className="cl-toc-list">
                      {group.items.map((item) => {
                        const isActive =
                          activeAnchorId === item.anchorId ||
                          (!activeAnchorId &&
                            versions[0]?.anchorId === item.anchorId);
                        return (
                          <li key={item.anchorId} className="cl-toc-item">
                            <a
                              href={`#/changelog?v=${item.anchorId}`}
                              className={`cl-toc-link ${isActive ? 'is-active' : ''}`}
                              onClick={(e) => {
                                e.preventDefault();
                                handleTocClick(item.anchorId);
                                window.history.replaceState(
                                  null,
                                  '',
                                  `#/changelog?v=${item.anchorId}`
                                );
                              }}
                            >
                              <span className="cl-toc-bullet" />
                              <span className="cl-toc-version">
                                {item.version}
                              </span>
                              {item.title && (
                                <span className="cl-toc-desc">
                                  {item.title}
                                </span>
                              )}
                            </a>
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                ))}
              </div>
            </nav>
          )}
        </div>

        {/* Right Version Timeline */}
        <div className="section-right-panel">
          {versions.length === 0 ? (
            <div className="cl-empty-card">
              <h3 className="cl-empty-title">{t('changelogEmptyTitle')}</h3>
              <p className="cl-empty-body">{t('changelogEmptyBody')}</p>
              <a
                href={`https://github.com/${repoSlug}/commits`}
                target="_blank"
                rel="noopener noreferrer"
                className="build-empty-link"
              >
                <span>{t('changelogViewCommits')}</span>
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
          ) : displayedVersions.length === 0 ? (
            <div className="cl-empty-card">
              <h3 className="cl-empty-title">
                {t('changelogSearchNoMatch', {
                  query: debouncedQuery.trim(),
                })}
              </h3>
              <button
                type="button"
                className="cl-reset-search-btn"
                onClick={() => onSearchQueryChange('')}
              >
                {t('changelogClearSearch')}
              </button>
            </div>
          ) : (
            <div className="cl-timeline">
              {displayedVersions.map((ver, idx) => {
                const prevYear =
                  idx > 0 ? displayedVersions[idx - 1].year : null;
                const showYearDivider =
                  Boolean(ver.year) && ver.year !== prevYear;
                const isLatest =
                  versions.length > 0 &&
                  ver.anchorId === versions[0].anchorId;

                return (
                  <React.Fragment key={ver.anchorId}>
                    {showYearDivider && (
                      <div className="cl-year-divider" aria-hidden="true">
                        <span className="cl-year-pill">{ver.year}</span>
                        <span className="cl-year-line" />
                      </div>
                    )}

                    <VersionNode
                      ver={ver}
                      isLatest={isLatest}
                      repoSlug={repoSlug}
                      debouncedQuery={debouncedQuery}
                      formatDate={formatDate}
                      formatRelativeTime={formatRelativeTime}
                      t={t}
                    />
                  </React.Fragment>
                );
              })}

              {!isSearching && remainingCount > 0 && (
                <div className="cl-load-more-wrap">
                  <button
                    type="button"
                    className="cl-load-more-btn"
                    onClick={() =>
                      setVisibleCount((prev) => prev + PAGE_INCREMENT)
                    }
                  >
                    <span>
                      {t('changelogShowMore', { remaining: remainingCount })}
                    </span>
                    <svg
                      viewBox="0 0 20 20"
                      width="16"
                      height="16"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      aria-hidden="true"
                    >
                      <path d="M5 7.5L10 12.5 15 7.5" />
                    </svg>
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </section>
  );
};
