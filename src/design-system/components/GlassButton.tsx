import React from "react";

export type GlassButtonVariant = "glass" | "accent" | "ghost";
export type GlassButtonSize = "sm" | "md" | "lg";

export type GlassButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: GlassButtonVariant;
  size?: GlassButtonSize;
};

export const GlassButton = React.forwardRef<HTMLButtonElement, GlassButtonProps>(
  ({ variant = "glass", size = "md", className, onPointerDown, children, ...rest }, ref) => {
    const classes = [
      "lg-button",
      `lg-button--${variant}`,
      size !== "md" && `lg-button--${size}`,
      className,
    ]
      .filter(Boolean)
      .join(" ");

    function handlePointerDown(event: React.PointerEvent<HTMLButtonElement>) {
      const rect = event.currentTarget.getBoundingClientRect();
      const x = ((event.clientX - rect.left) / rect.width) * 100;
      const y = ((event.clientY - rect.top) / rect.height) * 100;
      event.currentTarget.style.setProperty("--lg-press-x", `${x}%`);
      event.currentTarget.style.setProperty("--lg-press-y", `${y}%`);
      onPointerDown?.(event);
    }

    return (
      <button ref={ref} className={classes} onPointerDown={handlePointerDown} {...rest}>
        {children}
      </button>
    );
  },
);

GlassButton.displayName = "GlassButton";
