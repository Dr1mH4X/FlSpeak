import React from 'react';
import type { TranslationKey } from '../i18n/translations';
import type { ChangelogVersion } from '../types/release';
import { VersionNode } from './VersionNode';

interface LatestReleaseSectionProps {
  versions: ChangelogVersion[];
  repoSlug: string;
  formatDate: (iso: string | null | undefined) => string;
  formatRelativeTime: (iso: string | null | undefined) => string;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

export const LatestReleaseSection: React.FC<LatestReleaseSectionProps> = ({
  versions,
  repoSlug,
  formatDate,
  formatRelativeTime,
  t,
}) => {
  if (versions.length === 0) return null;

  const latest = versions[0];

  return (
    <section id="latest-release" className="section-block latest-release-section">
      <div className="section-two-col">
        {/* Left Sticky Header */}
        <div className="section-left-rail is-sticky-rail">
          <h2 className="section-heading">
            {t('changelogLatestReleaseHeading')}
          </h2>

          <p className="section-meta-badge">
            {latest.version} · {formatDate(latest.date)}
          </p>

          <p className="section-lead">
            {latest.title || t('changelogSummaryTitle')}
          </p>

          <div className="latest-release-nav-prompt">
            <a href="#/changelog" className="cl-go-archive-btn">
              <span>
                {t('changelogViewAllHistory', { total: versions.length })}
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
                <path d="M5 10h10M10 5l5 5-5 5" />
              </svg>
            </a>
          </div>
        </div>

        {/* Right Single Version Timeline */}
        <div className="section-right-panel">
          <div className="cl-timeline is-latest-only">
            <VersionNode
              key={latest.anchorId}
              ver={latest}
              isLatest={true}
              repoSlug={repoSlug}
              debouncedQuery=""
              formatDate={formatDate}
              formatRelativeTime={formatRelativeTime}
              t={t}
            />

            {/* Bottom View All CTA Bar */}
            <div className="cl-view-all-wrap">
              <a href="#/changelog" className="cl-view-all-cta">
                <span>
                  {t('changelogViewAllHistory', { total: versions.length })}
                </span>
                <svg
                  viewBox="0 0 20 20"
                  width="18"
                  height="18"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M5 10h10M10 5l5 5-5 5" />
                </svg>
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
