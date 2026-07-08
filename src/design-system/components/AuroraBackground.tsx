import React from "react";

export type AuroraBackgroundProps = React.HTMLAttributes<HTMLDivElement>;

/**
 * Transform-only animated gradient wash (L0). Pure CSS — no canvas/WebGL,
 * negligible CPU/GPU cost. Mount once behind page content, position:absolute
 * inside a position:relative ancestor (or position:fixed for full-viewport use).
 */
export function AuroraBackground({ className, ...rest }: AuroraBackgroundProps) {
  return (
    <div className={["lg-aurora", className].filter(Boolean).join(" ")} aria-hidden="true" {...rest}>
      <div className="lg-aurora__layer" />
      <div className="lg-aurora__layer lg-aurora__layer--reverse" />
    </div>
  );
}
