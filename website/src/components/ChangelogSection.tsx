import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { TranslationKey } from '../i18n/translations';
import type { ChangelogCategory, ChangelogVersion } from '../types/release';
import {
  filterChangelogVersions,
  normalizeAnchorId,
  splitHighlightSegments,
} from '../utils/parseChangelog';

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

const INITIAL_VISIBLE_COUNT = 6;
const PAGE_INCREMENT = 15;

function getCategoryTitleKey(cat: ChangelogCategory): TranslationKey {
  switch (cat) {
    case 'breaking':
      return 'changelogCatBreaking';
    case 'feat':
      return 'changelogCatFeat';
    case 'fix':
      return 'changelogCatFix';
    case 'perf':
      return 'changelogCatPerf';
    case 'revert':
      return 'changelogCatRevert';
  }
}

const HighlightedText: React.FC<{ text: string; query: string }> = ({
  text,
  query,
}) => {
  const segments = useMemo(
    () => splitHighlightSegments(text, query),
    [text, query]
  );
  return (
    <>
      {segments.map((seg, i) =>
        seg.highlighted ? (
          <mark key={i} className="cl-search-mark">
            {seg.text}
          </mark>
        ) : (
          <React.Fragment key={i}>{seg.text}</React.Fragment>
        )
      )}
    </>
  );
};

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

  return (
    <section id="changelog" className="section-block changelog-section">
      <div className="section-two-col">
        {/* Left Sticky Search & Stats Rail */}
        <div className="section-left-rail is-sticky-rail">
          <div className="section-index-row">
            <span className="section-index-num">{t('changelogIndex')}</span>
            <span className="section-index-line" aria-hidden="true" />
          </div>

          <h2 className="section-heading">{t('changelogTitle')}</h2>

          <p className="section-meta-badge">
            {versions.length > 0 && earliestDate
              ? t('changelogStats', {
                  count: versions.length,
                  since: earliestDate,
                })
              : t('changelogNoStats')}
          </p>

          <p className="section-lead">{t('changelogLead')}</p>

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
                const relativeStr = formatRelativeTime(ver.date);

                return (
                  <React.Fragment key={ver.anchorId}>
                    {showYearDivider && (
                      <div className="cl-year-divider" aria-hidden="true">
                        <span className="cl-year-pill">{ver.year}</span>
                        <span className="cl-year-line" />
                      </div>
                    )}

                    <article
                      id={ver.anchorId}
                      className={`cl-version-node ${isLatest ? 'is-latest' : ''}`}
                    >
                      {/* Sticky Version Header */}
                      <header className="cl-version-head">
                        <span
                          className={`cl-timeline-dot ${isLatest ? 'is-latest' : ''}`}
                          aria-hidden="true"
                        />

                        <div className="cl-version-title-group">
                          <h3 className="cl-version-tag">
                            <HighlightedText
                              text={ver.version}
                              query={debouncedQuery}
                            />
                          </h3>

                          <a
                            href={`#${ver.anchorId}`}
                            className="cl-version-anchor"
                            aria-label={`Anchor link for ${ver.version}`}
                          >
                            #
                          </a>

                          {isLatest && (
                            <span className="cl-badge-latest">
                              {t('changelogLatestBadge')}
                            </span>
                          )}

                          {!ver.isTagRelease && (
                            <span className="cl-badge-snapshot">
                              {t('changelogCommitNodeBadge')}
                            </span>
                          )}
                        </div>

                        <div className="cl-version-meta">
                          {ver.date && (
                            <time
                              dateTime={ver.date}
                              className="cl-version-date"
                            >
                              <span className="cl-date-primary">
                                {formatDate(ver.date)}
                              </span>
                              {relativeStr && (
                                <span className="cl-date-relative">
                                  · {relativeStr}
                                </span>
                              )}
                            </time>
                          )}

                          {ver.compareUrl && (
                            <a
                              href={ver.compareUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="cl-github-link"
                              aria-label={`${t('changelogViewOnGithub')} ${ver.version}`}
                            >
                              <span>GitHub</span>
                              <svg
                                viewBox="0 0 16 16"
                                width="12"
                                height="12"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                                aria-hidden="true"
                              >
                                <path d="M5 11L11 5M5 5h6v6" />
                              </svg>
                            </a>
                          )}
                        </div>
                      </header>

                      {/* Category Sections */}
                      <div className="cl-sections-stack">
                        {ver.sections.map((sec) => (
                          <div
                            key={sec.category}
                            className={`cl-group cl-cat-${sec.category}`}
                          >
                            <h4 className="cl-group-title">
                              <span
                                className={`cl-cat-dot is-${sec.category}`}
                                aria-hidden="true"
                              />
                              <span>{t(getCategoryTitleKey(sec.category))}</span>
                              <span className="cl-group-count">
                                {sec.items.length}
                              </span>
                            </h4>

                            <ul className="cl-items-list">
                              {sec.items.map((item) => (
                                <li key={item.id} className="cl-item">
                                  <div className="cl-item-content">
                                    {item.scope && (
                                      <code className="cl-item-scope">
                                        <HighlightedText
                                          text={item.scope}
                                          query={debouncedQuery}
                                        />
                                      </code>
                                    )}

                                    <span className="cl-item-desc">
                                      <HighlightedText
                                        text={item.description}
                                        query={debouncedQuery}
                                      />
                                    </span>

                                    {item.shortHash && item.commitUrl && (
                                      <a
                                        href={item.commitUrl}
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        className="cl-commit-hash"
                                      >
                                        <HighlightedText
                                          text={item.shortHash}
                                          query={debouncedQuery}
                                        />
                                      </a>
                                    )}
                                  </div>
                                </li>
                              ))}
                            </ul>
                          </div>
                        ))}
                      </div>
                    </article>
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
