import React from 'react';
import type { TranslationKey } from '../i18n/translations';

interface FactsGridProps {
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

interface FactItem {
  id: string;
  barColor?: string;
  titleKey: TranslationKey;
  bodyKey: TranslationKey;
  isPlaceholder?: boolean;
}

const FACTS: FactItem[] = [
  {
    id: 'tsclient',
    barColor: '#5556C9',
    titleKey: 'fact1Title',
    bodyKey: 'fact1Body',
  },
  {
    id: 'placeholder-2',
    titleKey: 'fact2Title',
    bodyKey: 'fact2Body',
    isPlaceholder: true,
  },
  {
    id: 'placeholder-3',
    titleKey: 'fact3Title',
    bodyKey: 'fact3Body',
    isPlaceholder: true,
  },
  {
    id: 'opensource',
    barColor: '#3FBF87',
    titleKey: 'fact4Title',
    bodyKey: 'fact4Body',
  },
];

export const FactsGrid: React.FC<FactsGridProps> = ({ t }) => {
  return (
    <div className="facts-grid" role="list">
      {FACTS.map((fact, idx) => {
        const isPlaceholder = Boolean(fact.isPlaceholder);
        const bodyText = t(fact.bodyKey);
        return (
          <article
            key={fact.id}
            role="listitem"
            className={`fact-card${isPlaceholder ? ' is-placeholder' : ''}`}
            aria-hidden={isPlaceholder ? true : undefined}
            style={
              {
                '--bar-color': fact.barColor,
                '--fact-delay': `${idx * 65}ms`,
              } as React.CSSProperties
            }
          >
            {!isPlaceholder && (
              <div className="fact-accent-bar" aria-hidden="true" />
            )}
            <h2 className="fact-title">{t(fact.titleKey)}</h2>
            {bodyText ? <p className="fact-body">{bodyText}</p> : null}
          </article>
        );
      })}
    </div>
  );
};
