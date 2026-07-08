import React, { useEffect, useRef, useState } from "react";
import { useLocalStorage } from "react-use";
import Lenis from "lenis";
import {
  AuroraBackground,
  GlassButton,
  GlassCard,
  GlassInput,
  GlassModal,
  GlassPanel,
  MouseLight,
  NoiseOverlay,
  PageTransition,
  ScrollReveal,
} from "./index";

type ThemeMode = "light" | "dark";
type DemoTab = "overview" | "tokens";

const showcaseCards = [
  { title: "云端同步", subtitle: "实时保存到 Supabase，随时随地继续记录。" },
  { title: "AI 识别", subtitle: "拍照即可估算热量与营养素，误差控制在合理范围。" },
  { title: "身体趋势", subtitle: "体重、体脂、围度长期曲线，一眼看清变化。" },
  { title: "运动闭环", subtitle: "自动导入 Apple 健康数据，训练与饮食联动分析。" },
];

export function DemoPage() {
  const [theme, setTheme] = useLocalStorage<ThemeMode>("lg-demo-theme", "light");
  const [modalOpen, setModalOpen] = useState(false);
  const [tab, setTab] = useState<DemoTab>("overview");
  const scrollRootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme || "light";
  }, [theme]);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const lenis = new Lenis({ duration: 1.1, smoothWheel: true });
    let frameId: number;
    function raf(time: number) {
      lenis.raf(time);
      frameId = requestAnimationFrame(raf);
    }
    frameId = requestAnimationFrame(raf);
    return () => {
      cancelAnimationFrame(frameId);
      lenis.destroy();
    };
  }, []);

  return (
    <div ref={scrollRootRef} className="lg-root lg-demo">
      <AuroraBackground className="lg-demo__bg" />
      <NoiseOverlay className="lg-demo__bg" />
      <MouseLight className="lg-demo__bg" />

      <div className="lg-demo__content">
        <header className="lg-demo__header">
          <div>
            <p className="lg-demo__eyebrow">Liquid Glass Design System</p>
            <h1 className="lg-demo__title">Apple 风格液态玻璃组件展示</h1>
            <p className="lg-demo__lede">
              一套独立、可复用的视觉系统 —— token 驱动、动效克制、玻璃只用于悬浮层。
              这里只是组件展示，不影响现有业务页面。
            </p>
          </div>
          <GlassButton
            variant="glass"
            onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
            type="button"
          >
            {theme === "dark" ? "切换到浅色" : "切换到深色"}
          </GlassButton>
        </header>

        <section className="lg-demo__section">
          <ScrollReveal as="div">
            <h2 className="lg-demo__sectionTitle">Glass Cards</h2>
          </ScrollReveal>
          <div className="lg-demo__grid">
            {showcaseCards.map((card, index) => (
              <ScrollReveal as="div" key={card.title} delay={index * 0.06}>
                <GlassCard interactive title={card.title} subtitle={card.subtitle} />
              </ScrollReveal>
            ))}
          </div>
        </section>

        <section className="lg-demo__section">
          <ScrollReveal as="div">
            <h2 className="lg-demo__sectionTitle">Buttons</h2>
          </ScrollReveal>
          <ScrollReveal as="div">
            <div className="lg-demo__row">
              <GlassButton variant="glass">Glass</GlassButton>
              <GlassButton variant="accent">Accent</GlassButton>
              <GlassButton variant="ghost">Ghost</GlassButton>
              <GlassButton variant="glass" size="sm">Small</GlassButton>
              <GlassButton variant="glass" size="lg">Large</GlassButton>
              <GlassButton variant="accent" disabled>Disabled</GlassButton>
            </div>
          </ScrollReveal>
        </section>

        <section className="lg-demo__section">
          <ScrollReveal as="div">
            <h2 className="lg-demo__sectionTitle">Input &amp; Panel</h2>
          </ScrollReveal>
          <ScrollReveal as="div">
            <GlassPanel className="lg-demo__panel">
              <GlassInput label="邮箱" placeholder="name@example.com" type="email" hint="用于接收登录链接" />
              <div className="lg-demo__row" style={{ marginTop: "var(--lg-space-4)" }}>
                <GlassButton variant="accent" onClick={() => setModalOpen(true)} type="button">
                  打开 Modal 示例
                </GlassButton>
              </div>
            </GlassPanel>
          </ScrollReveal>
        </section>

        <section className="lg-demo__section">
          <ScrollReveal as="div">
            <h2 className="lg-demo__sectionTitle">Page Transition</h2>
          </ScrollReveal>
          <ScrollReveal as="div">
            <div className="lg-demo__row" style={{ marginBottom: "var(--lg-space-4)" }}>
              <GlassButton
                variant={tab === "overview" ? "accent" : "ghost"}
                onClick={() => setTab("overview")}
                type="button"
              >
                Overview
              </GlassButton>
              <GlassButton
                variant={tab === "tokens" ? "accent" : "ghost"}
                onClick={() => setTab("tokens")}
                type="button"
              >
                Tokens
              </GlassButton>
            </div>
            <PageTransition pageKey={tab}>
              <GlassCard>
                {tab === "overview" ? (
                  <p>切换上方标签会触发 PageTransition 的淡入 + 位移过渡，可用于视图切换容器。</p>
                ) : (
                  <p>
                    Tokens 命名空间统一使用 <code>--lg-*</code> 前缀，
                    与业务页现有的 <code>--glass-*</code> 完全隔离，互不影响。
                  </p>
                )}
              </GlassCard>
            </PageTransition>
          </ScrollReveal>
        </section>

        <footer className="lg-demo__footer">
          <ScrollReveal as="div">
            <p>Liquid Glass Design System · Demo</p>
          </ScrollReveal>
        </footer>
      </div>

      <GlassModal open={modalOpen} onClose={() => setModalOpen(false)} title="Glass Modal 示例">
        <p>这是一个基于 Framer Motion 的玻璃弹层，支持 Esc 关闭、点击遮罩关闭。</p>
        <div className="lg-demo__row" style={{ marginTop: "var(--lg-space-4)" }}>
          <GlassButton variant="accent" onClick={() => setModalOpen(false)} type="button">
            知道了
          </GlassButton>
        </div>
      </GlassModal>
    </div>
  );
}
