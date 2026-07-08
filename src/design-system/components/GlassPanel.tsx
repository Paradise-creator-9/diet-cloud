import React from "react";

export type GlassPanelProps = React.HTMLAttributes<HTMLDivElement> & {
  as?: "div" | "section" | "aside";
};

export const GlassPanel = React.forwardRef<HTMLDivElement, GlassPanelProps>(
  ({ as = "div", className, children, ...rest }, ref) => {
    const Tag = as as React.ElementType;
    const classes = ["lg-glass", "lg-panel", className].filter(Boolean).join(" ");
    return (
      <Tag ref={ref} className={classes} {...rest}>
        {children}
      </Tag>
    );
  },
);

GlassPanel.displayName = "GlassPanel";
