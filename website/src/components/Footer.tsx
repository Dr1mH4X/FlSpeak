import React from 'react';
import type { TranslationKey } from '../i18n/translations';

interface FooterProps {
  repoSlug: string;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

export const Footer: React.FC<FooterProps> = ({ repoSlug, t }) => {
  const repoUrl = `https://github.com/${repoSlug}`;

  return (
    <footer className="site-footer">
      <div className="footer-inner">
        <div className="footer-brand-col">
          <div className="footer-brand-row">
            <span className="footer-brand-mark" aria-hidden="true">
              FL
            </span>
            <span className="footer-brand-name">{t('appTitle')}</span>
          </div>
          <p className="footer-note">{t('footerBoundaryNote')}</p>
          <p className="footer-license">{t('footerLicense')}</p>
        </div>

        <nav className="footer-links-col" aria-label="Footer links">
          <a
            href={repoUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="footer-ext-link"
          >
            {t('footerLinkGithub')}
          </a>
          <a
            href={`${repoUrl}/releases`}
            target="_blank"
            rel="noopener noreferrer"
            className="footer-ext-link"
          >
            {t('footerLinkReleases')}
          </a>
          <a
            href={`${repoUrl}/issues`}
            target="_blank"
            rel="noopener noreferrer"
            className="footer-ext-link"
          >
            {t('footerLinkIssues')}
          </a>
          <a
            href={`${repoUrl}/blob/main/LICENSE`}
            target="_blank"
            rel="noopener noreferrer"
            className="footer-ext-link"
          >
            {t('footerLinkLicense')}
          </a>
          <a
            href="https://github.com/flier/tsclient-rs"
            target="_blank"
            rel="noopener noreferrer"
            className="footer-ext-link"
          >
            {t('footerPoweredBy')}
          </a>
        </nav>
      </div>
    </footer>
  );
};
