import React from "react";

export type GlassCardProps = React.HTMLAttributes<HTMLDivElement> & {
  title?: string;
  subtitle?: string;
  interactive?: boolean;
};

export const GlassCard = React.forwardRef<HTMLDivElement, GlassCardProps>(
  ({ title, subtitle, interactive, className, children, ...rest }, ref) => {
    const classes = [
      "lg-glass",
      "lg-card",
      interactive && "lg-card--interactive",
      className,
    ]
      .filter(Boolean)
      .join(" ");

    return (
      <div ref={ref} className={classes} {...rest}>
        {(title || subtitle) && (
          <header>
            {title && <h3 className="lg-card__title">{title}</h3>}
            {subtitle && <p className="lg-card__subtitle">{subtitle}</p>}
          </header>
        )}
        {children}
      </div>
    );
  },
);

GlassCard.displayName = "GlassCard";
