import React, { useEffect, useRef } from "react";
import gsap from "gsap";

export type MouseLightProps = React.HTMLAttributes<HTMLDivElement>;

/**
 * A soft radial glow that follows the pointer within its container.
 * Uses gsap.quickTo to tween the glow's transform directly on the DOM node —
 * no React state/re-renders on mousemove, so it stays cheap even on
 * lower-end devices.
 */
export function MouseLight({ className, ...rest }: MouseLightProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const glowRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    const glow = glowRef.current;
    if (!container || !glow) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    // 容器自身 pointer-events: none 收不到事件,监听挂在承载它的父元素上
    const target = container.parentElement ?? container;

    const moveX = gsap.quickTo(glow, "x", { duration: 0.5, ease: "power3.out" });
    const moveY = gsap.quickTo(glow, "y", { duration: 0.5, ease: "power3.out" });

    function onPointerMove(event: PointerEvent) {
      const rect = container!.getBoundingClientRect();
      moveX(event.clientX - rect.left);
      moveY(event.clientY - rect.top);
    }

    function onPointerEnter() {
      gsap.to(glow, { opacity: 1, duration: 0.3 });
    }

    function onPointerLeave() {
      gsap.to(glow, { opacity: 0, duration: 0.4 });
    }

    target.addEventListener("pointermove", onPointerMove);
    target.addEventListener("pointerenter", onPointerEnter);
    target.addEventListener("pointerleave", onPointerLeave);
    return () => {
      target.removeEventListener("pointermove", onPointerMove);
      target.removeEventListener("pointerenter", onPointerEnter);
      target.removeEventListener("pointerleave", onPointerLeave);
    };
  }, []);

  return (
    <div ref={containerRef} className={["lg-mouse-light", className].filter(Boolean).join(" ")} aria-hidden="true" {...rest}>
      <div ref={glowRef} className="lg-mouse-light__glow" />
    </div>
  );
}
