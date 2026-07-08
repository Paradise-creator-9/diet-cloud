import React from "react";
import { AnimatePresence, motion } from "framer-motion";

export type PageTransitionProps = {
  pageKey: string | number;
  children: React.ReactNode;
  className?: string;
};

/**
 * Wrap route/view content with a stable `pageKey`; swapping the key
 * cross-fades + slides between views. Intended for view-switch containers
 * (this app has no router — pageKey can just be the active view name).
 */
export function PageTransition({ pageKey, children, className }: PageTransitionProps) {
  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={pageKey}
        className={className}
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -8 }}
        transition={{ duration: 0.32, ease: [0.16, 1, 0.3, 1] }}
      >
        {children}
      </motion.div>
    </AnimatePresence>
  );
}
