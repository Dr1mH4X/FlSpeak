import React, { useEffect, useRef, useState } from 'react';
import type { Locale, TranslationKey } from '../i18n/translations';
import type { ThemeMode } from '../hooks/useTheme';

interface NavbarProps {
  locale: Locale;
  onToggleLocale: () => void;
  theme: ThemeMode;
  onToggleTheme: (event: React.MouseEvent<HTMLElement>) => void;
  stars: number | null;
  repoUrl: string;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

export const Navbar: React.FC<NavbarProps> = ({
  onToggleLocale,
  theme,
  onToggleTheme,
  stars,
  repoUrl,
  t,
}) => {
  const [scrolled, setScrolled] = useState(false);
  const [progress, setProgress] = useState(0);
  const [displayStars, setDisplayStars] = useState<number>(0);
  const [starMinWidth, setStarMinWidth] = useState<number | undefined>(
    undefined
  );

  const navGroupRef = useRef<HTMLDivElement | null>(null);
  const measureStarRef = useRef<HTMLSpanElement | null>(null);
  const [inkStyle, setInkStyle] = useState<{
    left: number;
    width: number;
    opacity: number;
  }>({ left: 0, width: 0, opacity: 0 });

  useEffect(() => {
    let rafId = 0;
    const updateScroll = () => {
      const scrollTop = window.scrollY || document.documentElement.scrollTop;
      const docHeight =
        document.documentElement.scrollHeight -
        document.documentElement.clientHeight;
      setScrolled(scrollTop > 12);
      setProgress(
        docHeight > 0 ? Math.min(1, Math.max(0, scrollTop / docHeight)) : 0
      );
    };

    const onScroll = () => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(updateScroll);
    };

    updateScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      cancelAnimationFrame(rafId);
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
    };
  }, []);

  useEffect(() => {
    if (stars === null || stars < 0) return;

    if (measureStarRef.current) {
      const measured = measureStarRef.current.getBoundingClientRect().width;
      if (measured > 0) {
        setStarMinWidth(Math.ceil(measured));
      }
    }

    if (stars === 0) {
      setDisplayStars(0);
      return;
    }

    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

    if (prefersReducedMotion) {
      setDisplayStars(stars);
      return;
    }

    let rafId = 0;
    const duration = 1100;
    const start = performance.now();

    const step = (now: number) => {
      const elapsed = now - start;
      const progressRatio = Math.min(1, elapsed / duration);
      const eased = 1 - Math.pow(1 - progressRatio, 4);
      setDisplayStars(Math.round(eased * stars));
      if (progressRatio < 1) {
        rafId = requestAnimationFrame(step);
      }
    };

    rafId = requestAnimationFrame(step);
    return () => cancelAnimationFrame(rafId);
  }, [stars]);

  const handleItemEnter = (e: React.MouseEvent<HTMLElement>) => {
    const container = navGroupRef.current;
    if (!container) return;
    const target = e.currentTarget;
    const containerRect = container.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    setInkStyle({
      left: targetRect.left - containerRect.left,
      width: targetRect.width,
      opacity: 1,
    });
  };

  const handleGroupLeave = () => {
    setInkStyle((prev) => ({ ...prev, opacity: 0 }));
  };

  const formattedTargetStars =
    stars !== null && stars >= 0 ? stars.toLocaleString() : '';
  const formattedDisplayStars = displayStars.toLocaleString();

  return (
    <header className={`site-navbar ${scrolled ? 'is-scrolled' : ''}`}>
      <a href="#download" className="skip-link">
        {t('skipToDownloads')}
      </a>

      <div className="navbar-inner">
        <a href="#/" className="brand-link" aria-label={t('appTitle')}>
          <span className="brand-glyph" aria-hidden="true">
            <img
              src="/icon.png"
              alt=""
              className="brand-icon-img"
              onError={(e) => {
                // If icon.png fails to load, gracefully fall back to placeholder styling
                (e.currentTarget as HTMLElement).style.display = 'none';
              }}
            />
          </span>
          <span className="brand-wordmark">{t('appTitle')}</span>
        </a>

        <div
          className="nav-actions-group"
          ref={navGroupRef}
          onMouseLeave={handleGroupLeave}
        >
          <span
            className="nav-hover-ink"
            aria-hidden="true"
            style={{
              transform: `translate3d(${inkStyle.left}px, 0, 0)`,
              width: `${inkStyle.width}px`,
              opacity: inkStyle.opacity,
            }}
          />

          <a
            href="#/changelog"
            className="nav-item-link"
            onMouseEnter={handleItemEnter}
          >
            {t('navChangelog')}
          </a>

          <a
            href={repoUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="nav-item-link nav-github-link"
            aria-label={t('navGithub')}
            onMouseEnter={handleItemEnter}
          >
            <svg
              viewBox="0 0 24 24"
              width="17"
              height="17"
              fill="currentColor"
              aria-hidden="true"
            >
              <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.09 3.29 9.4 7.86 10.92.58.1.79-.25.79-.56 0-.28-.01-1.02-.02-2-3.2.7-3.88-1.54-3.88-1.54-.52-1.33-1.28-1.68-1.28-1.68-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.55-.29-5.23-1.28-5.23-5.68 0-1.26.45-2.28 1.18-3.09-.12-.29-.51-1.46.11-3.04 0 0 .97-.31 3.17 1.18a11.05 11.05 0 0 1 5.78 0c2.2-1.49 3.16-1.18 3.16-1.18.63 1.58.24 2.75.12 3.04.74.81 1.18 1.83 1.18 3.09 0 4.41-2.69 5.38-5.25 5.67.41.36.78 1.06.78 2.14 0 1.55-.01 2.79-.01 3.17 0 .31.21.67.8.56A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
            </svg>
            <span className="nav-github-text">GitHub</span>
            {stars !== null && stars > 0 && (
              <span className="nav-star-pill">
                <svg
                  viewBox="0 0 16 16"
                  width="12"
                  height="12"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path d="M8 .75l2.14 4.34 4.79.7-3.46 3.37.82 4.77L8 11.68l-4.29 2.25.82-4.77L1.07 5.79l4.79-.7L8 .75z" />
                </svg>
                <span
                  className="nav-star-number"
                  style={
                    starMinWidth ? { minWidth: `${starMinWidth}px` } : undefined
                  }
                >
                  {formattedDisplayStars}
                </span>
                <span
                  ref={measureStarRef}
                  className="nav-star-measure"
                  aria-hidden="true"
                >
                  {formattedTargetStars}
                </span>
              </span>
            )}
          </a>

          <span className="nav-divider" aria-hidden="true" />

          <button
            type="button"
            className="nav-icon-btn nav-lang-btn"
            onClick={onToggleLocale}
            onMouseEnter={handleItemEnter}
            aria-label={t('langSwitchLabel')}
          >
            <svg
              viewBox="0 0 24 24"
              width="16"
              height="16"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.9"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <circle cx="12" cy="12" r="9" />
              <path d="M3.6 9h16.8M3.6 15h16.8" />
              <path d="M12 3a14.5 14.5 0 0 0 0 18M12 3a14.5 14.5 0 0 1 0 18" />
            </svg>
            <span className="nav-lang-code">{t('langBadge')}</span>
          </button>

          <button
            type="button"
            className="nav-icon-btn nav-theme-btn"
            onClick={onToggleTheme}
            onMouseEnter={handleItemEnter}
            aria-label={
              theme === 'dark'
                ? t('themeSwitchToLight')
                : t('themeSwitchToDark')
            }
          >
            {theme === 'dark' ? (
              <svg
                viewBox="0 0 24 24"
                width="17"
                height="17"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.9"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <circle cx="12" cy="12" r="4.5" />
                <path d="M12 2.5v2.2M12 19.3v2.2M4.9 4.9l1.6 1.6M17.5 17.5l1.6 1.6M2.5 12h2.2M19.3 12h2.2M4.9 19.1l1.6-1.6M17.5 6.5l1.6-1.6" />
              </svg>
            ) : (
              <svg
                viewBox="0 0 24 24"
                width="17"
                height="17"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.9"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <path d="M20.4 14.6A8.5 8.5 0 0 1 9.4 3.6a8.5 8.5 0 1 0 11 11Z" />
              </svg>
            )}
          </button>
        </div>
      </div>

      <div
        className="navbar-progress-bar"
        aria-hidden="true"
        style={{ transform: `scaleX(${progress})` }}
      />
    </header>
  );
};
