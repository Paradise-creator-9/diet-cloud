import React from "react";

export type NoiseOverlayProps = React.HTMLAttributes<HTMLDivElement>;

/**
 * Static tiled feTurbulence texture painted once as a background-image —
 * breaks up flat glass gradients without banding. No animation, no JS cost.
 */
export function NoiseOverlay({ className, ...rest }: NoiseOverlayProps) {
  return <div className={["lg-noise", className].filter(Boolean).join(" ")} aria-hidden="true" {...rest} />;
}
