import React from "react";
import { motion, type Variants } from "framer-motion";

export type ScrollRevealProps = {
  children: React.ReactNode;
  className?: string;
  delay?: number;
  y?: number;
  as?: "div" | "section" | "li";
};

const baseVariants = (y: number): Variants => ({
  hidden: { opacity: 0, y },
  visible: { opacity: 1, y: 0 },
});

/**
 * Fades + slides content in once it scrolls into view (IntersectionObserver
 * under the hood via framer-motion's whileInView — no scroll-event listener).
 */
export function ScrollReveal({ children, className, delay = 0, y = 24, as = "div" }: ScrollRevealProps) {
  const MotionTag = motion[as];
  return (
    <MotionTag
      className={["lg-reveal", className].filter(Boolean).join(" ")}
      variants={baseVariants(y)}
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, margin: "-10% 0px" }}
      transition={{ duration: 0.6, delay, ease: [0.16, 1, 0.3, 1] }}
    >
      {children}
    </MotionTag>
  );
}
