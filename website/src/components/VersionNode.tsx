import React, { useMemo, useState } from 'react';
import type { TranslationKey } from '../i18n/translations';
import type {
  ChangelogCategory,
  ChangelogSection,
  ChangelogVersion,
} from '../types/release';
import { splitHighlightSegments } from '../utils/parseChangelog';

interface VersionNodeProps {
  ver: ChangelogVersion;
  isLatest: boolean;
  repoSlug: string;
  debouncedQuery: string;
  formatDate: (iso: string | null | undefined) => string;
  formatRelativeTime: (iso: string | null | undefined) => string;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

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
    case 'other':
      return 'changelogCatOther';
  }
}

export const HighlightedText: React.FC<{ text: string; query: string }> = ({
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

export const VersionNode: React.FC<VersionNodeProps> = ({
  ver,
  isLatest,
  debouncedQuery,
  formatDate,
  formatRelativeTime,
  t,
}) => {
  const [commitsExpanded, setCommitsExpanded] = useState(false);
  const relativeStr = formatRelativeTime(ver.date);

  const rawCommitsCount = useMemo(() => {
    if (!ver.rawSections) return 0;
    return ver.rawSections.reduce((acc, sec) => acc + sec.items.length, 0);
  }, [ver.rawSections]);

  // Automatically expand raw commits if user searched for something inside them
  const hasMatchedRawCommits = useMemo(() => {
    if (!debouncedQuery.trim() || !ver.rawSections) return false;
    return ver.rawSections.some((sec) => sec.items.length > 0);
  }, [debouncedQuery, ver.rawSections]);

  const showRawCommits = commitsExpanded || hasMatchedRawCommits;

  return (
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
            <HighlightedText text={ver.version} query={debouncedQuery} />
          </h3>

          <a
            href={`#/changelog?v=${ver.anchorId}`}
            className="cl-version-anchor"
            aria-label={`Anchor link for ${ver.version}`}
          >
            #
          </a>

          {ver.title && (
            <span className="cl-version-subject">
              <HighlightedText text={ver.title} query={debouncedQuery} />
            </span>
          )}

          {isLatest && (
            <span className="cl-badge-latest">{t('changelogLatestBadge')}</span>
          )}

          {!ver.isTagRelease && (
            <span className="cl-badge-snapshot">
              {t('changelogCommitNodeBadge')}
            </span>
          )}
        </div>

        <div className="cl-version-meta">
          {ver.date && (
            <time dateTime={ver.date} className="cl-version-date">
              <span className="cl-date-primary">{formatDate(ver.date)}</span>
              {relativeStr && (
                <span className="cl-date-relative"> · {relativeStr}</span>
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

      {/* Overview / Summary paragraph if present */}
      {ver.summary && (
        <div className="cl-version-summary">
          <p className="cl-summary-text">
            <HighlightedText text={ver.summary} query={debouncedQuery} />
          </p>
        </div>
      )}

      {/* Category Sections (Curated Highlights) */}
      <div className="cl-sections-stack">
        {ver.sections.map((sec: ChangelogSection) => (
          <div key={sec.category} className={`cl-group cl-cat-${sec.category}`}>
            <h4 className="cl-group-title">
              <span
                className={`cl-cat-dot is-${sec.category}`}
                aria-hidden="true"
              />
              <span>{t(getCategoryTitleKey(sec.category))}</span>
              <span className="cl-group-count">{sec.items.length}</span>
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

      {/* Contributors Box */}
      {ver.contributors && ver.contributors.length > 0 && (
        <div className="cl-contributors-box">
          <span className="cl-contributors-label">
            {t('changelogContributorsTitle')}
          </span>
          <div className="cl-contributors-list">
            {ver.contributors.map((handle) => (
              <a
                key={handle}
                href={`https://github.com/${handle.replace(/^@/, '')}`}
                target="_blank"
                rel="noopener noreferrer"
                className="cl-contributor-chip"
              >
                <span>{handle}</span>
              </a>
            ))}
          </div>
        </div>
      )}

      {/* Expandable Raw Commits Log */}
      {rawCommitsCount > 0 && ver.rawSections && (
        <div className="cl-raw-commits-container">
          <button
            type="button"
            className="cl-raw-commits-toggle"
            onClick={() => setCommitsExpanded((prev) => !prev)}
            aria-expanded={showRawCommits}
          >
            <svg
              viewBox="0 0 16 16"
              width="14"
              height="14"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className={`cl-toggle-chevron ${showRawCommits ? 'is-open' : ''}`}
              aria-hidden="true"
            >
              <path d="M4 6l4 4 4-4" />
            </svg>
            <span>
              {showRawCommits
                ? t('changelogCollapseCommits')
                : t('changelogExpandCommits', { count: rawCommitsCount })}
            </span>
          </button>

          {showRawCommits && (
            <div className="cl-raw-commits-panel">
              {ver.rawSections.map((sec) => (
                <div key={sec.category} className="cl-raw-group">
                  <h5 className="cl-raw-group-title">
                    <span
                      className={`cl-cat-dot is-${sec.category}`}
                      aria-hidden="true"
                    />
                    <span>{t(getCategoryTitleKey(sec.category))}</span>
                  </h5>
                  <ul className="cl-items-list is-raw-list">
                    {sec.items.map((item) => (
                      <li key={item.id} className="cl-item is-raw-item">
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
          )}
        </div>
      )}
    </article>
  );
};
