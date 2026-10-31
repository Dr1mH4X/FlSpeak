import { useCallback, useEffect, useState } from 'react';
import {
  formatTranslation,
  type Locale,
  type TranslationKey,
} from '../i18n/translations';

const STORAGE_KEY = 'flspeak.lang';

function getInitialLocale(): Locale {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved === 'zh' || saved === 'en') {
      return saved;
    }
  } catch {
    // Ignore storage error
  }
  if (typeof document !== 'undefined') {
    const htmlLang = (document.documentElement.lang || '').toLowerCase();
    if (htmlLang.startsWith('en')) return 'en';
    if (htmlLang.startsWith('zh')) return 'zh';
  }
  if (typeof navigator !== 'undefined') {
    const navLang = (navigator.language || '').toLowerCase();
    if (navLang.startsWith('zh')) return 'zh';
    if (navLang.startsWith('en')) return 'en';
  }
  return 'zh';
}

export function useI18n() {
  const [locale, setLocale] = useState<Locale>(getInitialLocale);

  useEffect(() => {
    if (typeof document !== 'undefined') {
      document.documentElement.lang = locale === 'zh' ? 'zh-CN' : 'en';
    }
    try {
      localStorage.setItem(STORAGE_KEY, locale);
    } catch {
      // Ignore storage error
    }
  }, [locale]);

  const toggleLocale = useCallback(() => {
    setLocale((prev) => (prev === 'zh' ? 'en' : 'zh'));
  }, []);

  const t = useCallback(
    (key: TranslationKey, vars?: Record<string, string | number>) => {
      return formatTranslation(locale, key, vars);
    },
    [locale]
  );

  const formatDate = useCallback(
    (isoOrDateStr: string | null | undefined): string => {
      if (!isoOrDateStr) return '';
      const parsed = new Date(
        isoOrDateStr.length === 10 ? `${isoOrDateStr}T00:00:00Z` : isoOrDateStr
      );
      if (Number.isNaN(parsed.getTime())) return isoOrDateStr;
      try {
        return new Intl.DateTimeFormat(locale === 'zh' ? 'zh-CN' : 'en-US', {
          year: 'numeric',
          month: 'short',
          day: 'numeric',
        }).format(parsed);
      } catch {
        return isoOrDateStr.slice(0, 10);
      }
    },
    [locale]
  );

  const formatRelativeTime = useCallback(
    (isoOrDateStr: string | null | undefined): string => {
      if (!isoOrDateStr) return '';
      const parsed = new Date(
        isoOrDateStr.length === 10 ? `${isoOrDateStr}T12:00:00Z` : isoOrDateStr
      );
      if (Number.isNaN(parsed.getTime())) return '';

      const diffMs = parsed.getTime() - Date.now();
      const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));

      try {
        const rtf = new Intl.RelativeTimeFormat(
          locale === 'zh' ? 'zh-CN' : 'en-US',
          { numeric: 'auto' }
        );
        if (Math.abs(diffDays) < 1) {
          return rtf.format(0, 'day');
        }
        if (Math.abs(diffDays) < 30) {
          return rtf.format(diffDays, 'day');
        }
        const diffMonths = Math.round(diffDays / 30);
        if (Math.abs(diffMonths) < 12) {
          return rtf.format(diffMonths, 'month');
        }
        const diffYears = Math.round(diffDays / 365);
        return rtf.format(diffYears, 'year');
      } catch {
        return '';
      }
    },
    [locale]
  );

  return {
    locale,
    setLocale,
    toggleLocale,
    t,
    formatDate,
    formatRelativeTime,
  };
}
