import React, {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import { FaGithub, FaStar } from 'react-icons/fa6';
import { LuGlobe, LuMoon, LuSun } from 'react-icons/lu';
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
  locale,
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

  const hoveredTargetRef = useRef<HTMLElement | null>(null);

  const syncInk = useCallback((target: HTMLElement | null) => {
    const container = navGroupRef.current;
    if (!container || !target) {
      setInkStyle((prev) => ({ ...prev, opacity: 0 }));
      return;
    }
    const containerRect = container.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    setInkStyle({
      left: targetRect.left - containerRect.left,
      width: targetRect.width,
      opacity: 1,
    });
  }, []);

  const handleItemEnter = (e: React.MouseEvent<HTMLElement>) => {
    hoveredTargetRef.current = e.currentTarget;
    syncInk(e.currentTarget);
  };

  const handleGroupLeave = () => {
    hoveredTargetRef.current = null;
    setInkStyle((prev) => ({ ...prev, opacity: 0 }));
  };

  // Re-align hover ink immediately before paint when locale changes
  useLayoutEffect(() => {
    if (hoveredTargetRef.current) {
      syncInk(hoveredTargetRef.current);
    }
  }, [locale, syncInk]);

  // Re-align hover ink whenever navbar elements change dimensions (e.g. text width, font loading)
  useEffect(() => {
    const container = navGroupRef.current;
    if (!container || typeof ResizeObserver === 'undefined') return;

    const observer = new ResizeObserver(() => {
      if (hoveredTargetRef.current) {
        syncInk(hoveredTargetRef.current);
      }
    });

    observer.observe(container);
    Array.from(container.children).forEach((child) => {
      if (!child.classList.contains('nav-hover-ink')) {
        observer.observe(child);
      }
    });

    return () => observer.disconnect();
  }, [syncInk]);

  const handleToggleLocale = (e: React.MouseEvent<HTMLButtonElement>) => {
    hoveredTargetRef.current = e.currentTarget;
    onToggleLocale();
    requestAnimationFrame(() => {
      if (hoveredTargetRef.current) {
        syncInk(hoveredTargetRef.current);
      }
    });
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
            <FaGithub size={17} aria-hidden="true" />
            <span className="nav-github-text">GitHub</span>
            {stars !== null && stars > 0 && (
              <span className="nav-star-pill">
                <FaStar size={11} aria-hidden="true" />
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
            onClick={handleToggleLocale}
            onMouseEnter={handleItemEnter}
            aria-label={t('langSwitchLabel')}
          >
            <LuGlobe size={16} strokeWidth={1.9} aria-hidden="true" />
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
              <LuSun size={17} strokeWidth={1.9} aria-hidden="true" />
            ) : (
              <LuMoon size={17} strokeWidth={1.9} aria-hidden="true" />
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
