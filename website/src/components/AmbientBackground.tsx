import React, { useEffect, useRef } from 'react';

export const AmbientBackground: React.FC = () => {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) return;

    let rafId = 0;
    let pendingX = 0;
    let pendingY = 0;
    let hasPending = false;

    const handlePointerMove = (e: PointerEvent) => {
      pendingX = e.clientX;
      pendingY = e.clientY;
      if (!hasPending) {
        hasPending = true;
        rafId = requestAnimationFrame(() => {
          el.style.setProperty('--aura-x', `${pendingX}px`);
          el.style.setProperty('--aura-y', `${pendingY}px`);
          hasPending = false;
        });
      }
    };

    window.addEventListener('pointermove', handlePointerMove, {
      passive: true,
    });
    return () => {
      cancelAnimationFrame(rafId);
      window.removeEventListener('pointermove', handlePointerMove);
    };
  }, []);

  return (
    <div ref={containerRef} className="ambient-backdrop" aria-hidden="true">
      <div className="ambient-mesh-primary" />
      <div className="ambient-dot-matrix" />
      <div className="ambient-acoustic-rings">
        <span className="acoustic-ring ring-1" />
        <span className="acoustic-ring ring-2" />
        <span className="acoustic-ring ring-3" />
      </div>
      <div className="ambient-vignette" />
    </div>
  );
};
