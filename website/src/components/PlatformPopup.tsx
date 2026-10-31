import React, { useEffect, useId, useRef, useState } from 'react';
import type { TranslationKey } from '../i18n/translations';
import type { PlatformId } from '../types/release';

interface PlatformPopupProps {
  selectedPlatform: PlatformId;
  onSelectPlatform: (platform: PlatformId) => void;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

export const PLATFORM_ORDER: PlatformId[] = [
  'windows',
  'macos',
  'linux',
  'android',
];

export const PlatformIcon: React.FC<{
  platform: PlatformId;
  size?: number;
  className?: string;
}> = ({ platform, size = 18, className }) => {
  switch (platform) {
    case 'windows':
      return (
        <svg
          viewBox="0 0 24 24"
          width={size}
          height={size}
          fill="currentColor"
          className={className}
          aria-hidden="true"
        >
          <path d="M3 4.8L10.8 3.7v7.5H3V4.8zm8.9-1.25L21 2.2v9H11.9V3.55zM3 12.6h7.8v7.6L3 19.1v-6.5zm8.9 0H21v9.2l-9.1-1.3v-7.9z" />
        </svg>
      );
    case 'macos':
      return (
        <svg
          viewBox="0 0 24 24"
          width={size}
          height={size}
          fill="currentColor"
          className={className}
          aria-hidden="true"
        >
          <path d="M16.52 12.66c.02 2.45 2.15 3.26 2.17 3.27-.02.06-.34 1.16-1.12 2.3-.67.98-1.37 1.96-2.47 1.98-1.08.02-1.43-.64-2.66-.64-1.24 0-1.63.62-2.64.66-1.06.04-1.87-1.06-2.55-2.04-1.38-2-2.44-5.64-1.02-8.11.71-1.23 1.98-2 3.35-2.02 1.05-.02 2.04.7 2.68.7.64 0 1.84-.87 3.1-.74.53.02 2.01.21 2.96 1.6-.08.05-1.77 1.03-1.8 3.04zM14.48 6.4c.56-.68.94-1.63.84-2.58-.81.03-1.79.54-2.37 1.22-.52.6-.98 1.56-.86 2.49.9.07 1.83-.45 2.39-1.13z" />
        </svg>
      );
    case 'linux':
      return (
        <svg
          viewBox="0 0 24 24"
          width={size}
          height={size}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.85"
          strokeLinecap="round"
          strokeLinejoin="round"
          className={className}
          aria-hidden="true"
        >
          <rect x="3" y="4" width="18" height="16" rx="3.5" />
          <path d="M7.5 9.5L10.5 12l-3 2.5M12.5 15h4" />
        </svg>
      );
    case 'android':
      return (
        <svg
          viewBox="0 0 24 24"
          width={size}
          height={size}
          fill="currentColor"
          className={className}
          aria-hidden="true"
        >
          <path d="M17.6 9.48l1.84-3.18a.6.6 0 0 0-1.04-.6l-1.88 3.24a11.4 11.4 0 0 0-9.04 0L5.6 5.7a.6.6 0 0 0-1.04.6l1.84 3.18A10.7 10.7 0 0 0 2 18h20a10.7 10.7 0 0 0-4.4-8.52zM7.5 14.5a1 1 0 1 1 0-2 1 1 0 0 1 0 2zm9 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2z" />
        </svg>
      );
  }
};

export function getPlatformLabelKey(platform: PlatformId): TranslationKey {
  switch (platform) {
    case 'windows':
      return 'platformWindows';
    case 'macos':
      return 'platformMacos';
    case 'linux':
      return 'platformLinux';
    case 'android':
      return 'platformAndroid';
  }
}

function getPlatformSubKey(platform: PlatformId): TranslationKey {
  switch (platform) {
    case 'windows':
      return 'platformSubWindows';
    case 'macos':
      return 'platformSubMacos';
    case 'linux':
      return 'platformSubLinux';
    case 'android':
      return 'platformSubAndroid';
  }
}

export const PlatformPopup: React.FC<PlatformPopupProps> = ({
  selectedPlatform,
  onSelectPlatform,
  t,
}) => {
  const [open, setOpen] = useState(false);
  const [focusedIndex, setFocusedIndex] = useState<number>(() =>
    Math.max(0, PLATFORM_ORDER.indexOf(selectedPlatform))
  );

  const menuId = useId();
  const wrapperRef = useRef<HTMLSpanElement | null>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);

  useEffect(() => {
    const idx = PLATFORM_ORDER.indexOf(selectedPlatform);
    if (idx !== -1) setFocusedIndex(idx);
  }, [selectedPlatform]);

  useEffect(() => {
    if (!open) return;

    const handlePointerDown = (e: MouseEvent | TouchEvent) => {
      if (
        wrapperRef.current &&
        !wrapperRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    };

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        setOpen(false);
        triggerRef.current?.focus();
      }
    };

    document.addEventListener('mousedown', handlePointerDown);
    document.addEventListener('touchstart', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('mousedown', handlePointerDown);
      document.removeEventListener('touchstart', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [open]);

  useEffect(() => {
    if (open) {
      const activeIdx = Math.max(0, PLATFORM_ORDER.indexOf(selectedPlatform));
      setFocusedIndex(activeIdx);
      requestAnimationFrame(() => {
        optionRefs.current[activeIdx]?.focus();
      });
    }
  }, [open, selectedPlatform]);

  const handleTriggerKeyDown = (e: React.KeyboardEvent<HTMLButtonElement>) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      setOpen(true);
    }
  };

  const handleMenuKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      const next = (focusedIndex + 1) % PLATFORM_ORDER.length;
      setFocusedIndex(next);
      optionRefs.current[next]?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      const prev =
        (focusedIndex - 1 + PLATFORM_ORDER.length) % PLATFORM_ORDER.length;
      setFocusedIndex(prev);
      optionRefs.current[prev]?.focus();
    } else if (e.key === 'Home') {
      e.preventDefault();
      setFocusedIndex(0);
      optionRefs.current[0]?.focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      const last = PLATFORM_ORDER.length - 1;
      setFocusedIndex(last);
      optionRefs.current[last]?.focus();
    }
  };

  const handleSelect = (platform: PlatformId) => {
    onSelectPlatform(platform);
    setOpen(false);
    triggerRef.current?.focus();
  };

  const activeLabel = t(getPlatformLabelKey(selectedPlatform));

  return (
    <span ref={wrapperRef} className="fls-popup-anchor">
      <button
        ref={triggerRef}
        type="button"
        className={`fls-popup-trigger ${open ? 'is-open' : ''}`}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={menuId}
        aria-label={t('heroPlatformTriggerAria', { platform: activeLabel })}
        onClick={() => setOpen((prev) => !prev)}
        onKeyDown={handleTriggerKeyDown}
      >
        <span className="fls-popup-trigger-icon">
          <PlatformIcon platform={selectedPlatform} size={22} />
        </span>
        <span className="fls-popup-trigger-label">{activeLabel}</span>
        <span
          className={`fls-popup-chevron ${open ? 'is-open' : ''}`}
          aria-hidden="true"
        >
          <svg
            viewBox="0 0 24 24"
            width="20"
            height="20"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M6 9l6 6 6-6" />
          </svg>
        </span>
      </button>

      <div
        id={menuId}
        role="listbox"
        aria-label={t('platformPopupTitle')}
        className={`fls-popup-surface ${open ? 'is-open' : ''}`}
        onKeyDown={handleMenuKeyDown}
      >
        <div className="fls-popup-inner">
          {PLATFORM_ORDER.map((plat, index) => {
            const isSelected = plat === selectedPlatform;
            const label = t(getPlatformLabelKey(plat));
            const subtitle = t(getPlatformSubKey(plat));
            return (
              <button
                key={plat}
                ref={(el) => {
                  optionRefs.current[index] = el;
                }}
                type="button"
                role="option"
                aria-selected={isSelected}
                tabIndex={open && focusedIndex === index ? 0 : -1}
                className={`fls-popup-option ${isSelected ? 'is-selected' : ''}`}
                style={{
                  transitionDelay: open ? `${index * 22}ms` : '0ms',
                }}
                onClick={() => handleSelect(plat)}
              >
                <span className="fls-popup-option-icon">
                  <PlatformIcon platform={plat} size={19} />
                </span>
                <span className="fls-popup-option-copy">
                  <span className="fls-popup-option-title">{label}</span>
                  <span className="fls-popup-option-sub">{subtitle}</span>
                </span>
                <span
                  className={`fls-popup-option-check ${isSelected ? 'is-visible' : ''}`}
                  aria-hidden="true"
                >
                  <svg
                    viewBox="0 0 24 24"
                    width="18"
                    height="18"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.4"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <path d="M20 6L9 17l-5-5" />
                  </svg>
                </span>
              </button>
            );
          })}
        </div>
      </div>
    </span>
  );
};
