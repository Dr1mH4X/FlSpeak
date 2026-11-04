import React, { useEffect, useId, useRef, useState } from 'react';
import { FaAndroid, FaApple, FaLinux, FaWindows } from 'react-icons/fa6';
import { LuCheck, LuChevronDown } from 'react-icons/lu';
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
      return <FaWindows size={size} className={className} aria-hidden="true" />;
    case 'macos':
      return <FaApple size={size} className={className} aria-hidden="true" />;
    case 'linux':
      return <FaLinux size={size} className={className} aria-hidden="true" />;
    case 'android':
      return <FaAndroid size={size} className={className} aria-hidden="true" />;
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
          <LuChevronDown size={20} strokeWidth={2.2} />
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
                  <LuCheck size={18} strokeWidth={2.4} />
                </span>
              </button>
            );
          })}
        </div>
      </div>
    </span>
  );
};
