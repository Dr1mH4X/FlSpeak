import React from 'react';
import type { TranslationKey } from '../i18n/translations';

interface FactsGridProps {
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

const FACTS: Array<{
  id: string;
  barColor: string;
  titleKey: TranslationKey;
  bodyKey: TranslationKey;
}> = [
  {
    id: 'boundary',
    barColor: '#5556C9',
    titleKey: 'fact1Title',
    bodyKey: 'fact1Body',
  },
  {
    id: 'audio',
    barColor: '#3FBF87',
    titleKey: 'fact2Title',
    bodyKey: 'fact2Body',
  },
  {
    id: 'actor',
    barColor: '#D97706',
    titleKey: 'fact3Title',
    bodyKey: 'fact3Body',
  },
  {
    id: 'ui',
    barColor: '#8B5CF6',
    titleKey: 'fact4Title',
    bodyKey: 'fact4Body',
  },
];

export const FactsGrid: React.FC<FactsGridProps> = ({ t }) => {
  return (
    <div className="facts-grid" role="list">
      {FACTS.map((fact, idx) => (
        <article
          key={fact.id}
          role="listitem"
          className="fact-card"
          style={
            {
              '--bar-color': fact.barColor,
              '--fact-delay': `${idx * 65}ms`,
            } as React.CSSProperties
          }
        >
          <div className="fact-accent-bar" aria-hidden="true" />
          <h2 className="fact-title">{t(fact.titleKey)}</h2>
          <p className="fact-body">{t(fact.bodyKey)}</p>
        </article>
      ))}
    </div>
  );
};
