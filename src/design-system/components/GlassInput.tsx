import React, { useId } from "react";

export type GlassInputProps = React.InputHTMLAttributes<HTMLInputElement> & {
  label?: string;
  hint?: string;
};

export const GlassInput = React.forwardRef<HTMLInputElement, GlassInputProps>(
  ({ label, hint, className, id, ...rest }, ref) => {
    const generatedId = useId();
    const inputId = id || generatedId;

    return (
      <div className="lg-input-wrap">
        {label && (
          <label className="lg-input-label" htmlFor={inputId}>
            {label}
          </label>
        )}
        <input ref={ref} id={inputId} className={["lg-input", className].filter(Boolean).join(" ")} {...rest} />
        {hint && <span className="lg-input-hint">{hint}</span>}
      </div>
    );
  },
);

GlassInput.displayName = "GlassInput";
