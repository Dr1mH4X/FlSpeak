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

    let targetX = 0.5;
    let targetY = 0.35;
    let currentX = 0.5;
    let currentY = 0.35;
    let rafId = 0;

    const animate = () => {
      currentX += (targetX - currentX) * 0.06;
      currentY += (targetY - currentY) * 0.06;
      el.style.setProperty('--aura-x', `${(currentX * 100).toFixed(2)}%`);
      el.style.setProperty('--aura-y', `${(currentY * 100).toFixed(2)}%`);
      rafId = requestAnimationFrame(animate);
    };

    const handlePointerMove = (e: PointerEvent) => {
      if (window.innerWidth <= 0 || window.innerHeight <= 0) return;
      targetX = Math.min(0.85, Math.max(0.15, e.clientX / window.innerWidth));
      targetY = Math.min(0.75, Math.max(0.12, e.clientY / window.innerHeight));
    };

    rafId = requestAnimationFrame(animate);
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
      <div className="ambient-mesh-secondary" />
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
