import { useCallback, useEffect, useState } from 'react';
import { flushSync } from 'react-dom';

export type ThemeMode = 'light' | 'dark';

const STORAGE_KEY = 'flspeak.theme';

function getInitialTheme(): ThemeMode {
  if (typeof document !== 'undefined') {
    const attr = document.documentElement.getAttribute('data-theme');
    if (attr === 'light' || attr === 'dark') {
      return attr;
    }
  }
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved === 'light' || saved === 'dark') {
      return saved;
    }
  } catch {
    // Storage unavailable
  }
  if (
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-color-scheme: light)').matches
  ) {
    return 'light';
  }
  return 'dark';
}

function applyThemeToDom(theme: ThemeMode) {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  root.setAttribute('data-theme', theme);
  root.classList.toggle('dark', theme === 'dark');
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // Ignore storage error
  }
}

export function useTheme() {
  const [theme, setTheme] = useState<ThemeMode>(getInitialTheme);

  useEffect(() => {
    applyThemeToDom(theme);
  }, [theme]);

  const toggleTheme = useCallback(
    (event?: React.MouseEvent<HTMLElement>) => {
      const nextTheme: ThemeMode = theme === 'dark' ? 'light' : 'dark';
      const prefersReducedMotion =
        typeof window !== 'undefined' &&
        window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

      const docWithTransition = document as Document & {
        startViewTransition?: (callback: () => void) => {
          ready: Promise<void>;
        };
      };

      if (
        !event ||
        prefersReducedMotion ||
        typeof docWithTransition.startViewTransition !== 'function'
      ) {
        applyThemeToDom(nextTheme);
        setTheme(nextTheme);
        return;
      }

      const rect = event.currentTarget.getBoundingClientRect();
      const x =
        rect.width > 0
          ? rect.left + rect.width / 2
          : event.clientX || window.innerWidth / 2;
      const y =
        rect.height > 0
          ? rect.top + rect.height / 2
          : event.clientY || window.innerHeight / 2;

      const maxRadius = Math.hypot(
        Math.max(x, window.innerWidth - x),
        Math.max(y, window.innerHeight - y)
      );

      try {
        const transition = docWithTransition.startViewTransition(() => {
          flushSync(() => {
            applyThemeToDom(nextTheme);
            setTheme(nextTheme);
          });
        });

        transition.ready
          .then(() => {
            document.documentElement.animate(
              {
                clipPath: [
                  `circle(0px at ${x}px ${y}px)`,
                  `circle(${maxRadius}px at ${x}px ${y}px)`,
                ],
              },
              {
                duration: 480,
                easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
                pseudoElement: '::view-transition-new(root)',
              }
            );
          })
          .catch(() => {
            // Ignore animation interruption
          });
      } catch {
        applyThemeToDom(nextTheme);
        setTheme(nextTheme);
      }
    },
    [theme]
  );

  return { theme, setTheme, toggleTheme };
}
