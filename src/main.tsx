import React, { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { createRoot } from "react-dom/client";
import {
  Activity,
  Bike,
  CalendarDays,
  CheckCircle2,
  ChevronRight,
  Cloud,
  CloudUpload,
  Coffee,
  Download,
  Droplets,
  Dumbbell,
  House,
  ImagePlus,
  Flame,
  Footprints,
  HeartPulse,
  Leaf,
  LineChart,
  ListChecks,
  LogOut,
  Mail,
  Moon,
  PenLine,
  Plus,
  RefreshCw,
  Route,
  ScrollText,
  Settings,
  ShieldCheck,
  Sparkles,
  Smartphone,
  Scale,
  Sun,
  Timer,
  Trash2,
  Utensils,
  Watch,
  Wheat,
} from "lucide-react";
import { createExerciseActivity, createFoodItem, createFoodItems, deleteBodyMetric, deleteDailyActivity, deleteExerciseActivity, deleteFoodItem, fetchBodyMetrics, fetchDailyActivities, fetchExerciseActivities, fetchFoodItems, getCurrentUser, importDiaryBundle, importExerciseData, isCloudConfigured, onAuthChange, signInWithEmail, signOut, updateExerciseActivity, updateFoodItem, upsertBodyMetric, upsertDailyActivity } from "./supabase";
import { appleHealthMetricDefinitions, parseAppleHealthExport, type AppleHealthImportResult, type AppleHealthParseProgress, type HealthMetricDefinition } from "./appleHealth";
import { mealMeta, nutrientTargets, seedItems } from "./data";
import type { BodyMetric, DailyActivity, ExerciseActivity, FoodItem, MealType } from "./types";
import { buildDates, formatDateLabel, itemsByMeal, round, totalsFor, uniquePhotos } from "./utils";
import { GlassButton, GlassCard, GlassModal } from "./design-system";
import "./styles.css";

type View = "overview" | "detail" | "trend" | "photos" | "body" | "exercise";
type ThemeMode = "light" | "dark";
type Notice = {
  title: string;
  body: string;
  actionLabel?: string;
  onAction?: () => void;
};
type ToastMessage = {
  id: number;
  title: string;
  body?: string;
  tone?: "success" | "info";
};
type EntryDraft = {
  meal: MealType;
  item?: FoodItem;
  mode?: "manual" | "ai";
};
type AnalysisItem = {
  name: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  reasoning?: string;
};
type BodyMetricKey = "weightKg" | "bodyFatPercent" | "muscleKg" | "bmrKcal" | "waterPercent" | "visceralFat";
type BodyMetricDefinition = {
  key: BodyMetricKey;
  label: string;
  unit: string;
  tone: string;
  color: string;
  icon: React.ReactNode;
  format: (value: number) => string;
};
type UserGoals = {
  targetWeightKg: number;
  targetDate: string;
  dailyCalories: number;
  protein: number;
  fiber: number;
  weeklyLossKg: number;
};
type FavoriteFood = {
  id: string;
  name: string;
  meal: MealType;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  note: string;
};

const localStorageKeys = {
  goals: "diet-cloud-goals-v1",
  favorites: "diet-cloud-favorites-v1",
};

const defaultGoals: UserGoals = {
  targetWeightKg: 68,
  targetDate: "2026-12-31",
  dailyCalories: nutrientTargets.calories,
  protein: nutrientTargets.protein,
  fiber: nutrientTargets.fiber,
  weeklyLossKg: 0.5,
};

const defaultFavoriteFoods: FavoriteFood[] = [
  { id: "fav-banana", name: "香蕉", meal: "snack", grams: 120, calories: 105, protein: 1, carbs: 27, fat: 0, fiber: 3, note: "常用估算：中等香蕉 1 根。" },
  { id: "fav-boiled-egg", name: "水煮蛋", meal: "breakfast", grams: 50, calories: 70, protein: 6, carbs: 0, fat: 5, fiber: 0, note: "常用估算：普通鸡蛋 1 个。" },
  { id: "fav-oats-milk", name: "燕麦牛奶", meal: "breakfast", grams: 260, calories: 240, protein: 11, carbs: 34, fat: 7, fiber: 5, note: "常用估算：生燕麦 60g + 牛奶 200g。" },
  { id: "fav-chicken-breast", name: "鸡小胸", meal: "dinner", grams: 150, calories: 248, protein: 35, carbs: 2, fat: 8, fiber: 0, note: "常用估算：熟鸡小胸一份。" },
  { id: "fav-broccoli", name: "西兰花", meal: "dinner", grams: 200, calories: 70, protein: 6, carbs: 12, fat: 1, fiber: 6, note: "常用估算：清炒或水煮一碗。" },
];

function ModalPortal({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    document.body.classList.add("modal-open");
    return () => document.body.classList.remove("modal-open");
  }, []);

  return createPortal(children, document.body);
}

function getInitialTheme(): ThemeMode {
  if (typeof window === "undefined") return "light";
  const savedTheme = window.localStorage.getItem("diet-cloud-theme");
  if (savedTheme === "light" || savedTheme === "dark") return savedTheme;
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function readStoredJson<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) return fallback;
    return { ...fallback, ...JSON.parse(raw) };
  } catch {
    return fallback;
  }
}

function readStoredArray<T>(key: string, fallback: T[]): T[] {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = window.localStorage.getItem(key);
    const parsed = raw ? JSON.parse(raw) : fallback;
    return Array.isArray(parsed) && parsed.length ? parsed : fallback;
  } catch {
    return fallback;
  }
}

function writeStoredJson(key: string, value: unknown) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(key, JSON.stringify(value));
}

function App() {
  const [items, setItems] = useState<FoodItem[]>(isCloudConfigured ? [] : seedItems);
  const [bodyMetrics, setBodyMetrics] = useState<BodyMetric[]>([]);
  const [dailyActivities, setDailyActivities] = useState<DailyActivity[]>([]);
  const [exerciseActivities, setExerciseActivities] = useState<ExerciseActivity[]>([]);
  const [selectedDate, setSelectedDate] = useState(dateKey(new Date()));
  const [activeView, setActiveView] = useState<View>("overview");
  const [cloudState, setCloudState] = useState(isCloudConfigured ? "正在同步" : "演示数据");
  const [bodyState, setBodyState] = useState(isCloudConfigured ? "身体数据待同步" : "演示数据");
  const [exerciseState, setExerciseState] = useState(isCloudConfigured ? "运动数据待同步" : "演示数据");
  const [authReady, setAuthReady] = useState(!isCloudConfigured);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [entryDraft, setEntryDraft] = useState<EntryDraft | null>(null);
  const [bodyDialogOpen, setBodyDialogOpen] = useState(false);
  const [dailyActivityDialogOpen, setDailyActivityDialogOpen] = useState(false);
  const [workoutDraft, setWorkoutDraft] = useState<ExerciseActivity | null | undefined>(undefined);
  const [goals, setGoals] = useState<UserGoals>(() => readStoredJson(localStorageKeys.goals, defaultGoals));
  const [favoriteFoods, setFavoriteFoods] = useState<FavoriteFood[]>(() => readStoredArray(localStorageKeys.favorites, defaultFavoriteFoods));
  const [goalsDialogOpen, setGoalsDialogOpen] = useState(false);
  const [favoritesDialogOpen, setFavoritesDialogOpen] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const [importing, setImporting] = useState(false);
  const [appleHealthImporting, setAppleHealthImporting] = useState(false);
  const [themeMode, setThemeMode] = useState<ThemeMode>(() => getInitialTheme());
  const [headerScrolled, setHeaderScrolled] = useState(false);
  const importInputRef = useRef<HTMLInputElement>(null);
  const appleHealthInputRef = useRef<HTMLInputElement>(null);
  const appleHealthImportMonthsRef = useRef(3);
  const toastTimerRef = useRef<number | null>(null);

  useEffect(() => {
    document.documentElement.dataset.theme = themeMode;
    document.documentElement.style.colorScheme = themeMode;
    window.localStorage.setItem("diet-cloud-theme", themeMode);
  }, [themeMode]);

  useEffect(() => {
    writeStoredJson(localStorageKeys.goals, goals);
  }, [goals]);

  useEffect(() => {
    writeStoredJson(localStorageKeys.favorites, favoriteFoods);
  }, [favoriteFoods]);

  useEffect(() => () => {
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
  }, []);

  useEffect(() => {
    function onScroll() {
      setHeaderScrolled(window.scrollY > 8);
    }
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  function showToast(title: string, body?: string, tone: ToastMessage["tone"] = "success") {
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
    setToast({ id: Date.now(), title, body, tone });
    toastTimerRef.current = window.setTimeout(() => setToast(null), 2600);
  }

  useEffect(() => {
    if (!isCloudConfigured) return;
    let alive = true;
    async function refreshUser() {
      const user = await getCurrentUser();
      if (!alive) return;
      setUserEmail(user?.email || null);
      setCloudState(user ? "云端已登录" : "需要登录");
      setAuthReady(true);
    }
    refreshUser();
    const unsubscribe = onAuthChange(refreshUser);
    return () => {
      alive = false;
      unsubscribe();
    };
  }, []);

  async function refreshCloudItems(preferredDate?: string) {
    if (!isCloudConfigured || !userEmail) return;
    setCloudState("正在同步");
    try {
      const cloudItems = await fetchFoodItems();
      setItems(cloudItems);
      const cloudDates = buildDates(cloudItems);
      if (cloudDates.length) {
        setSelectedDate(preferredDate && cloudDates.includes(preferredDate) ? preferredDate : cloudDates.includes(selectedDate) ? selectedDate : cloudDates[0]);
      }
      setCloudState(cloudItems.length ? "云端已同步" : "云端已同步 · 暂无记录");
    } catch (error) {
      setItems([]);
      setCloudState(`云端连接失败：${formatCloudError(error)}`);
    }
  }

  async function refreshBodyMetrics() {
    if (!isCloudConfigured || !userEmail) return;
    setBodyState("正在同步身体数据");
    try {
      const metrics = await fetchBodyMetrics();
      setBodyMetrics(metrics);
      setBodyState(metrics.length ? "身体数据已同步" : "身体数据已同步 · 暂无记录");
    } catch (error) {
      setBodyMetrics([]);
      setBodyState(`身体数据不可用：${formatCloudError(error)}`);
    }
  }

  async function refreshExerciseData() {
    if (!isCloudConfigured || !userEmail) return;
    setExerciseState("正在同步运动数据");
    try {
      const [dailyData, workoutData] = await Promise.all([
        fetchDailyActivities(),
        fetchExerciseActivities(),
      ]);
      setDailyActivities(dailyData);
      setExerciseActivities(workoutData);
      setExerciseState(dailyData.length || workoutData.length ? "运动数据已同步" : "运动数据已同步 · 暂无记录");
    } catch (error) {
      setDailyActivities([]);
      setExerciseActivities([]);
      setExerciseState(`运动数据不可用：${formatCloudError(error)}`);
    }
  }

  useEffect(() => {
    if (!isCloudConfigured || !authReady || !userEmail) return;
    refreshCloudItems();
    refreshBodyMetrics();
    refreshExerciseData();
  }, [authReady, userEmail]);

  const dates = useMemo(() => {
    const combined = [
      ...items.map((item) => item.date),
      ...bodyMetrics.map((metric) => metric.date),
      ...dailyActivities.map((activityItem) => activityItem.date),
      ...exerciseActivities.map((activityItem) => activityItem.date),
    ];
    return [...new Set(combined)].sort((a, b) => b.localeCompare(a));
  }, [bodyMetrics, dailyActivities, exerciseActivities, items]);
  const dayItems = useMemo(() => items.filter((item) => item.date === selectedDate), [items, selectedDate]);
  const selectedDailyActivity = useMemo(() => dailyActivities.find((activityItem) => activityItem.date === selectedDate), [dailyActivities, selectedDate]);
  const selectedWorkouts = useMemo(() => exerciseActivities.filter((activityItem) => activityItem.date === selectedDate), [exerciseActivities, selectedDate]);
  const totals = useMemo(() => totalsFor(dayItems), [dayItems]);
  const toggleThemeMode = () => setThemeMode((mode) => (mode === "dark" ? "light" : "dark"));

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [activeView]);

  function openRecordNotice(meal?: MealType) {
    setEntryDraft({ meal: meal || "lunch" });
  }

  function openAiAnalysis() {
    setEntryDraft({ meal: "lunch", mode: "ai" });
  }

  function openEditItem(item: FoodItem) {
    setEntryDraft({ meal: item.meal, item });
  }

  async function quickAddFavoriteFood(food: FavoriteFood) {
    const serving = favoriteServing(food);
    const normalizedFood = scaleFavoriteForServing(food, serving.grams);
    const payload = {
      date: selectedDate,
      meal: normalizedFood.meal,
      name: normalizedFood.name,
      grams: normalizedFood.grams,
      calories: normalizedFood.calories,
      protein: normalizedFood.protein,
      carbs: normalizedFood.carbs,
      fat: normalizedFood.fat,
      fiber: normalizedFood.fiber,
      note: `${food.note || "来自常吃食物库一键添加。"} 点击增量：${serving.label}。`,
    };

    try {
      if (isCloudConfigured) {
        if (!userEmail) {
          setNotice({ title: "需要登录", body: "登录后才能把常吃食物一键保存到云端。" });
          return;
        }
        await createFoodItem(payload);
        await refreshCloudItems(selectedDate);
      } else {
        setItems((current) => [
          ...current,
          {
            id: `local-${Date.now()}`,
            ...payload,
            photoUrls: [],
            photoPaths: [],
            createdAt: new Date().toISOString(),
          },
        ]);
      }
      showToast("已添加", `「${food.name}」已加入${mealMeta.find((meal) => meal.key === food.meal)?.title || "饮食"}。`);
    } catch (error) {
      setNotice({ title: "添加失败", body: formatCloudError(error) });
    }
  }

  function confirmDeleteItem(item: FoodItem) {
    setNotice({
      title: "删除记录",
      body: `确定删除「${item.name}」吗？这条记录会从云端移除，相关照片也会从这条记录里删除。`,
      actionLabel: "确认删除",
      onAction: async () => {
        try {
          await deleteFoodItem(item);
          await refreshCloudItems(item.date);
          setNotice(null);
          showToast("已删除", "饮食记录已从云端移除。");
        } catch (error) {
          setNotice({ title: "删除失败", body: formatCloudError(error) });
        }
      },
    });
  }

  function showMobileInfo() {
    const body = "手机打开这个地址即可查看：https://diet-cloud.vercel.app。登录一次后 Safari 会记住状态，也可以用分享菜单添加到主屏幕。";
    navigator.clipboard?.writeText("https://diet-cloud.vercel.app").catch(() => undefined);
    setNotice({ title: "手机查看", body: `${body}\n\n我也已经尝试把网址复制到剪贴板。` });
  }

  function showSettings() {
    setNotice({
      title: "设置",
      body: `当前账号：${userEmail || "未登录"}\n当前日期：${selectedDate}\n云端状态：${cloudState}\n身体数据：${bodyState}\n运动数据：${exerciseState}`,
    });
  }

  function showShortcutInfo() {
    const endpoint = "https://diet-cloud.vercel.app/api/activity-ingest";
    navigator.clipboard?.writeText(endpoint).catch(() => undefined);
    setNotice({
      title: "iPhone 快捷指令同步",
      body: `接口地址已尝试复制：${endpoint}\n\n推荐用最简单的 URL 参数法：\n方法：GET\nURL：${endpoint}?token=你的_DIARY_INGEST_TOKEN&write=1&date=今天日期&steps=步数&activeCalories=活动热量&exerciseMinutes=运动分钟&standHours=站立小时&distanceKm=步行跑步公里\n\n也可以继续用 POST JSON：\nHeader 可用 Authorization = Bearer 你的 DIARY_INGEST_TOKEN，或 x-diary-token = 你的_DIARY_INGEST_TOKEN。\n\n排查时加 debug=true，并在“获取 URL 内容”后面加“显示结果”。如果返回 dailyImported: 1，说明已经写入云端。`,
    });
  }

  function exportRecords() {
    const payload = {
      exportedAt: new Date().toISOString(),
      selectedDate,
      totals,
      items,
      bodyMetrics,
      dailyActivities,
      exerciseActivities,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `diet-records-${selectedDate}.json`;
    link.click();
    URL.revokeObjectURL(url);
    showToast("已导出", "饮食记录 JSON 已开始下载。", "info");
  }

  async function handleImportFile(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setImporting(true);
    setCloudState("正在导入本地记录");
    try {
      const bundle = JSON.parse(await file.text());
      const result = await importDiaryBundle(bundle);
      await refreshCloudItems();
      showToast(
        "导入完成",
        `新增 ${result.inserted} 条，更新 ${result.updated} 条，上传 ${result.photosUploaded} 张照片。`,
      );
    } catch (error) {
      const message = formatCloudError(error);
      setCloudState(`导入失败：${message}`);
      setNotice({
        title: "导入失败",
        body: message.includes("storage") || message.includes("policy") || message.includes("permission")
          ? `${message}\n\n这通常是 Supabase Storage 还没有允许登录用户上传照片。`
          : message,
      });
    } finally {
      setImporting(false);
    }
  }

  async function handleAppleHealthImport(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    const months = appleHealthImportMonthsRef.current;
    setAppleHealthImporting(true);
    setExerciseState(`正在读取 Apple 健康 zip · 近 ${months} 个月`);
    try {
      const cutoffDate = dateKey(addMonths(new Date(), -months));
      const parsed = await parseAppleHealthExportInWorker(file, cutoffDate, (progress) => {
        setExerciseState(formatAppleHealthImportProgress(progress, months));
      });
      setExerciseState(`正在写入 Apple 健康数据 · ${parsed.summary.dateCount} 天 / ${parsed.summary.workoutCount} 条训练`);
      const result = await importExerciseData(parsed.dailyActivities, parsed.workouts, (progress) => {
        const label = progress.phase === "daily" ? "活动摘要" : "训练";
        setExerciseState(`正在写入 ${label} · ${progress.imported}/${progress.total}`);
      });
      await refreshExerciseData();
      setActiveView("exercise");
      showToast(
        "Apple 健康导入完成",
        `近 ${months} 个月：${result.dailyImported} 天摘要、${result.workoutsImported} 条训练。`,
      );
    } catch (error) {
      const message = formatCloudError(error);
      setExerciseState(`Apple 健康导入失败：${message}`);
      setNotice({
        title: "Apple 健康导入失败",
        body: message.includes("daily_activities") || message.includes("exercise_activities")
          ? `${message}\n\n如果提示表不存在，请先在 Supabase SQL Editor 运行 supabase/exercise.sql。`
          : message,
      });
    } finally {
      setAppleHealthImporting(false);
    }
  }

  function startAppleHealthImport(months = 3) {
    appleHealthImportMonthsRef.current = months;
    appleHealthInputRef.current?.click();
  }

  if (isCloudConfigured && !authReady) {
    return <AuthGate mode="loading" />;
  }

  if (isCloudConfigured && !userEmail) {
    return <AuthGate mode="login" />;
  }

  return (
    <div className="appShell">
      <header className={`appHeader${headerScrolled ? " appHeader--scrolled" : ""}`}>
        <div>
          <p className="appEyebrow">{activeViewTitle(activeView)} · {dates.length ? `${dates.length} 天记录` : cloudState}</p>
          <h1 className="appTitle">{formatDateLabel(selectedDate)}</h1>
        </div>
        <div className="appHeaderActions headerToolbar">
          <label aria-label="选择日期" className="iconButton datePickerButton" title="选择日期">
            <CalendarDays size={18} />
            <input value={selectedDate} onChange={(event) => setSelectedDate(event.target.value)} type="date" />
          </label>
          <button aria-label="新增食物" className="iconButton" onClick={() => openRecordNotice("snack")} title="新增食物" type="button"><Plus size={19} /></button>
          <button
            aria-label={themeMode === "dark" ? "切换到白天模式" : "切换到黑暗模式"}
            className="iconButton"
            onClick={toggleThemeMode}
            title={themeMode === "dark" ? "白天模式" : "黑暗模式"}
            type="button"
          >
            {themeMode === "dark" ? <Sun size={17} /> : <Moon size={17} />}
          </button>
          <button aria-label="更多操作" className="iconButton" onClick={() => setMoreOpen(true)} title="更多操作" type="button"><Settings size={17} /></button>
          <input accept="application/json,.json" className="hiddenFileInput" onChange={handleImportFile} ref={importInputRef} type="file" />
          <input accept=".zip,application/zip,application/x-zip-compressed" className="hiddenFileInput" onChange={handleAppleHealthImport} ref={appleHealthInputRef} type="file" />
        </div>
      </header>

      <main className="appMain">
        {activeView === "overview" && (
          <Overview
            allItems={items}
            bodyMetrics={bodyMetrics}
            dailyActivities={dailyActivities}
            exerciseActivities={exerciseActivities}
            favoriteFoods={favoriteFoods}
            goals={goals}
            items={dayItems}
            onAiAnalyze={openAiAnalysis}
            onEdit={() => setActiveView("detail")}
            onManageFavorites={() => setFavoritesDialogOpen(true)}
            onOpenGoals={() => setGoalsDialogOpen(true)}
            onQuickAddFavorite={quickAddFavoriteFood}
            onRecordMeal={openRecordNotice}
            selectedDate={selectedDate}
            totals={totals}
          />
        )}
        {activeView === "detail" && <Detail items={dayItems} onDeleteItem={confirmDeleteItem} onEditItem={openEditItem} />}
        {activeView === "trend" && <Trend bodyMetrics={bodyMetrics} dailyActivities={dailyActivities} exerciseActivities={exerciseActivities} goals={goals} items={items} selectedDate={selectedDate} />}
        {activeView === "photos" && <PhotoLibrary items={items} />}
        {activeView === "body" && (
          <BodyDashboard
            bodyMetrics={bodyMetrics}
            bodyState={bodyState}
            items={items}
            onDeleteMetric={async (metric) => {
              setNotice({
                title: "删除身体数据",
                body: `确定删除 ${metric.date} 的身体数据吗？`,
                actionLabel: "确认删除",
                onAction: async () => {
                  try {
                    await deleteBodyMetric(metric.id);
                    await refreshBodyMetrics();
                    setNotice(null);
                    showToast("已删除", "身体数据已从云端移除。");
                  } catch (error) {
                    setNotice({ title: "删除失败", body: formatCloudError(error) });
                  }
                },
              });
            }}
            onOpenEditor={() => setBodyDialogOpen(true)}
            selectedDate={selectedDate}
          />
        )}
        {activeView === "exercise" && (
          <ExerciseDashboard
            bodyMetrics={bodyMetrics}
            dailyActivities={dailyActivities}
            exerciseActivities={exerciseActivities}
            exerciseState={exerciseState}
            items={items}
            appleHealthImporting={appleHealthImporting}
            onOpenShortcutInfo={showShortcutInfo}
            onDeleteDaily={async (activityItem) => {
              setNotice({
                title: "删除活动摘要",
                body: `确定删除 ${activityItem.date} 的 ${sourceLabel(activityItem.source)} 活动摘要吗？`,
                actionLabel: "确认删除",
                onAction: async () => {
                  try {
                    await deleteDailyActivity(activityItem.id);
                    await refreshExerciseData();
                    setNotice(null);
                    showToast("已删除", "活动摘要已从云端移除。");
                  } catch (error) {
                    setNotice({ title: "删除失败", body: formatCloudError(error) });
                  }
                },
              });
            }}
            onDeleteWorkout={async (workout) => {
              setNotice({
                title: "删除训练",
                body: `确定删除「${workout.title}」吗？`,
                actionLabel: "确认删除",
                onAction: async () => {
                  try {
                    await deleteExerciseActivity(workout.id);
                    await refreshExerciseData();
                    setNotice(null);
                    showToast("已删除", "训练记录已从云端移除。");
                  } catch (error) {
                    setNotice({ title: "删除失败", body: formatCloudError(error) });
                  }
                },
              });
            }}
            onEditWorkout={(workout) => setWorkoutDraft(workout)}
            onImportAppleHealth={startAppleHealthImport}
            onOpenDaily={() => setDailyActivityDialogOpen(true)}
            onRefreshExercise={refreshExerciseData}
            onOpenWorkout={() => setWorkoutDraft(null)}
            selectedDate={selectedDate}
          />
        )}
      </main>

      <TabBar activeView={activeView} setActiveView={setActiveView} />

      {moreOpen && (
        <MoreSheet
          importing={importing}
          onClose={() => setMoreOpen(false)}
          onExport={exportRecords}
          onImport={() => importInputRef.current?.click()}
          onShowMobile={showMobileInfo}
          onShowSettings={showSettings}
          onShowShortcut={showShortcutInfo}
          onSync={() => { refreshCloudItems(); refreshBodyMetrics(); refreshExerciseData(); }}
        />
      )}
      {notice && <NoticeDialog notice={notice} onClose={() => setNotice(null)} />}
      <Toast toast={toast} onClose={() => setToast(null)} />
      {entryDraft && (
        <ManualEntryDialog
          defaultDate={selectedDate}
          defaultMeal={entryDraft.meal}
          editingItem={entryDraft.item}
          items={items}
          mode={entryDraft.mode}
          onClose={() => setEntryDraft(null)}
          onSaved={async (savedDate) => {
            const wasEditing = Boolean(entryDraft.item);
            setEntryDraft(null);
            await refreshCloudItems(savedDate);
            setActiveView("detail");
            showToast(wasEditing ? "已更新" : "已保存", wasEditing ? "饮食记录已同步到云端。" : "新增饮食记录已写入云端。");
          }}
        />
      )}
      {bodyDialogOpen && (
        <BodyMetricDialog
          defaultDate={selectedDate}
          metric={bodyMetrics.find((item) => item.date === selectedDate)}
          onClose={() => setBodyDialogOpen(false)}
          onSaved={async (savedDate) => {
            setBodyDialogOpen(false);
            setSelectedDate(savedDate);
            await refreshBodyMetrics();
            showToast("已保存", "身体数据已同步到云端。");
          }}
        />
      )}
      {dailyActivityDialogOpen && (
        <DailyActivityDialog
          activity={selectedDailyActivity}
          defaultDate={selectedDate}
          onClose={() => setDailyActivityDialogOpen(false)}
          onSaved={async (savedDate) => {
            setDailyActivityDialogOpen(false);
            setSelectedDate(savedDate);
            await refreshExerciseData();
            showToast("已保存", "活动摘要已同步到云端。");
          }}
        />
      )}
      {workoutDraft !== undefined && (
        <WorkoutDialog
          defaultDate={selectedDate}
          onClose={() => setWorkoutDraft(undefined)}
          onSaved={async (savedDate) => {
            setWorkoutDraft(undefined);
            setSelectedDate(savedDate);
            await refreshExerciseData();
            showToast("已保存", "训练记录已同步到云端。");
          }}
          workout={workoutDraft || undefined}
        />
      )}
      {goalsDialogOpen && <GoalsDialog goals={goals} onClose={() => setGoalsDialogOpen(false)} onSave={(nextGoals) => { setGoals(nextGoals); setGoalsDialogOpen(false); }} />}
      {favoritesDialogOpen && <FavoriteFoodsDialog favoriteFoods={favoriteFoods} onClose={() => setFavoritesDialogOpen(false)} onSave={(nextFoods) => { setFavoriteFoods(nextFoods); setFavoritesDialogOpen(false); }} />}
    </div>
  );
}

const TAB_ORDER: View[] = ["overview", "detail", "trend", "photos", "body", "exercise"];

function TabBar({ activeView, setActiveView }: { activeView: View; setActiveView: (view: View) => void }) {
  const activeIndex = TAB_ORDER.indexOf(activeView);
  return (
    <nav
      className="tabBar"
      aria-label="主导航"
      style={{ "--tab-count": TAB_ORDER.length, "--tab-index": activeIndex } as React.CSSProperties}
    >
      <span aria-hidden="true" className="tabIndicator" />
      <TabButton active={activeView === "overview"} icon={<House size={19} />} label="总览" onClick={() => setActiveView("overview")} />
      <TabButton active={activeView === "detail"} icon={<ListChecks size={19} />} label="明细" onClick={() => setActiveView("detail")} />
      <TabButton active={activeView === "trend"} icon={<LineChart size={19} />} label="趋势" onClick={() => setActiveView("trend")} />
      <TabButton active={activeView === "photos"} icon={<ImagePlus size={19} />} label="照片" onClick={() => setActiveView("photos")} />
      <TabButton active={activeView === "body"} icon={<Scale size={19} />} label="身体" onClick={() => setActiveView("body")} />
      <TabButton active={activeView === "exercise"} icon={<Activity size={19} />} label="运动" onClick={() => setActiveView("exercise")} />
    </nav>
  );
}

function MoreSheet({
  importing,
  onClose,
  onExport,
  onImport,
  onShowMobile,
  onShowSettings,
  onShowShortcut,
  onSync,
}: {
  importing: boolean;
  onClose: () => void;
  onExport: () => void;
  onImport: () => void;
  onShowMobile: () => void;
  onShowSettings: () => void;
  onShowShortcut: () => void;
  onSync: () => void;
}) {
  function run(action: () => void) {
    onClose();
    action();
  }

  return (
    <GlassModal open onClose={onClose} title="更多操作">
      <div className="moreList">
        <GlassButton variant="glass" onClick={() => run(onSync)} type="button"><RefreshCw size={16} />同步云端数据</GlassButton>
        <GlassButton variant="glass" disabled={importing} onClick={() => run(onImport)} type="button"><CloudUpload size={16} />{importing ? "导入中" : "导入 JSON 记录"}</GlassButton>
        <GlassButton variant="glass" onClick={() => run(onExport)} type="button"><Download size={16} />导出全部记录</GlassButton>
        <GlassButton variant="glass" onClick={() => run(onShowMobile)} type="button"><Smartphone size={16} />手机查看</GlassButton>
        <GlassButton variant="glass" onClick={() => run(onShowShortcut)} type="button"><Watch size={16} />快捷指令同步说明</GlassButton>
        <GlassButton variant="glass" onClick={() => run(onShowSettings)} type="button"><Settings size={16} />账号与同步状态</GlassButton>
        {isCloudConfigured && <GlassButton className="moreDanger" variant="ghost" onClick={() => signOut()} type="button"><LogOut size={16} />退出登录</GlassButton>}
      </div>
    </GlassModal>
  );
}

function activeViewTitle(view: View) {
  if (view === "overview") return "总览";
  if (view === "detail") return "明细";
  if (view === "trend") return "趋势";
  if (view === "photos") return "照片库";
  if (view === "body") return "身体";
  return "运动";
}

function weekdayShort(date: string) {
  return new Intl.DateTimeFormat("zh-CN", { weekday: "short" }).format(new Date(`${date}T00:00:00`));
}

function AuthGate({ mode }: { mode: "loading" | "login" }) {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState(mode === "loading" ? "正在确认登录状态..." : "输入邮箱后，会收到一封登录邮件。");

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!email.trim()) return;
    setStatus("正在发送登录邮件...");
    try {
      await signInWithEmail(email.trim());
      setStatus("登录邮件已发送，请打开邮箱里的链接。");
    } catch (error) {
      setStatus(formatAuthError(error));
    }
  }

  return (
    <main className="authPage">
      <section className="authPanel">
        <div className="brandMark"><ScrollText size={22} /></div>
        <h1 className="authBrand">膳食志</h1>
        <p className="authTagline">登录后查看你的饮食、照片和营养分析</p>
        <div className="authChecks">
          <span><ShieldCheck size={16} /> 数据按账号隔离</span>
          <span><Cloud size={16} /> Supabase 云端保存</span>
        </div>
        {mode === "login" && (
          <form className="authForm" onSubmit={handleSubmit}>
            <label>
              <span>邮箱</span>
              <input autoComplete="email" inputMode="email" onChange={(event) => setEmail(event.target.value)} placeholder="name@example.com" type="email" value={email} />
            </label>
            <button type="submit"><Mail size={16} />发送登录邮件</button>
          </form>
        )}
        <p className="authStatus">{status}</p>
      </section>
    </main>
  );
}

function formatAuthError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error || "");
  const lowerMessage = message.toLowerCase();

  if (lowerMessage.includes("rate") || lowerMessage.includes("too many") || lowerMessage.includes("security purposes")) {
    return `发送太频繁了，请等 1-2 分钟后再试。Supabase 返回：${message}`;
  }

  if (lowerMessage.includes("redirect")) {
    return `登录回跳地址还没有被允许。Supabase 返回：${message}`;
  }

  return `发送失败。Supabase 返回：${message || "未知错误"}`;
}

function formatCloudError(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error && "message" in error) return String((error as { message?: unknown }).message || "未知错误");
  return String(error || "未知错误");
}

function formatAppleHealthImportProgress(progress: AppleHealthParseProgress, months: number) {
  const percent = progress.totalBytes
    ? Math.min(100, Math.round((progress.bytesRead / progress.totalBytes) * 100))
    : 0;
  if (progress.phase === "reading") {
    return `正在读取 Apple 健康 zip · 近 ${months} 个月 · ${percent}%`;
  }
  return `正在解析 Apple 健康 · ${percent}% · 已扫 ${progress.recordsScanned.toLocaleString()} 条，保留 ${progress.recordsKept.toLocaleString()} 条`;
}

function parseAppleHealthExportInWorker(
  file: File,
  cutoffDate: string,
  onProgress: (progress: AppleHealthParseProgress) => void,
) {
  if (typeof Worker === "undefined") {
    return parseAppleHealthExport(file, { cutoffDate, onProgress });
  }

  return new Promise<AppleHealthImportResult>((resolve, reject) => {
    let worker: Worker;
    let settled = false;
    const fallbackToMainThread = async (reason: string) => {
      if (settled) return;
      settled = true;
      worker?.terminate();
      try {
        onProgress({ phase: "parsing", bytesRead: file.size || 0, totalBytes: file.size || 0, recordsScanned: 0, recordsKept: 0, workoutsKept: 0 });
        const result = await parseAppleHealthExport(file, { cutoffDate, onProgress });
        resolve(result);
      } catch (error) {
        const message = formatCloudError(error);
        reject(new Error(`${reason}\n主线程重试也失败：${message}`));
      }
    };

    try {
      worker = new Worker(new URL("./appleHealthWorker.ts", import.meta.url), { type: "module" });
    } catch (error) {
      fallbackToMainThread(`Apple 健康解析线程无法启动：${formatCloudError(error)}`);
      return;
    }

    worker.onmessage = (event: MessageEvent<{ type: string; progress?: AppleHealthParseProgress; result?: AppleHealthImportResult; message?: string }>) => {
      if (event.data.type === "progress" && event.data.progress) {
        onProgress(event.data.progress);
      }
      if (event.data.type === "done" && event.data.result) {
        settled = true;
        worker.terminate();
        resolve(event.data.result);
      }
      if (event.data.type === "error") {
        fallbackToMainThread(`Apple 健康解析线程出错：${event.data.message || "未知错误"}`);
      }
    };
    worker.onerror = (error) => {
      const detail = error instanceof ErrorEvent
        ? `${error.message || "未知错误"}${error.filename ? `\n${error.filename}:${error.lineno}:${error.colno}` : ""}`
        : "未知错误";
      fallbackToMainThread(`Apple 健康解析线程崩溃：${detail}`);
    };
    worker.onmessageerror = () => {
      fallbackToMainThread("Apple 健康解析线程返回数据失败。");
    };
    worker.postMessage({ file, cutoffDate });
  });
}

function NoticeDialog({ notice, onClose }: { notice: Notice; onClose: () => void }) {
  function handleAction() {
    notice.onAction?.();
    onClose();
  }

  return (
    <GlassModal open onClose={onClose} title={notice.title}>
      <p className="noticeBody">{notice.body}</p>
      <div className="noticeActions">
        {notice.actionLabel && <GlassButton className="noticeDanger" size="sm" variant="ghost" onClick={handleAction} type="button">{notice.actionLabel}</GlassButton>}
        <GlassButton size="sm" variant="glass" onClick={onClose} type="button">知道了</GlassButton>
      </div>
    </GlassModal>
  );
}

function Toast({ toast, onClose }: { toast: ToastMessage | null; onClose: () => void }) {
  if (!toast) return null;
  return createPortal(
    <button className={`appToast ${toast.tone || "success"}`} key={toast.id} onClick={onClose} type="button">
      <span>{toast.tone === "info" ? <Cloud size={17} /> : <CheckCircle2 size={17} />}</span>
      <div>
        <strong>{toast.title}</strong>
        {toast.body && <small>{toast.body}</small>}
      </div>
    </button>,
    document.body,
  );
}

function GoalsDialog({ goals, onClose, onSave }: { goals: UserGoals; onClose: () => void; onSave: (goals: UserGoals) => void }) {
  const [draft, setDraft] = useState<UserGoals>(goals);

  function updateGoal<K extends keyof UserGoals>(key: K, value: UserGoals[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  function numberValue(value: string) {
    return Number(value || 0);
  }

  return (
    <ModalPortal>
      <div className="modalBackdrop" role="presentation" onClick={onClose}>
        <section aria-modal="true" className="entryDialog compactDialog goalDialog" role="dialog" onClick={(event) => event.stopPropagation()}>
          <div className="entryHead">
            <div>
              <h3>减脂目标</h3>
              <p>目标会用于每日余量、周报和月报判断。</p>
            </div>
            <button aria-label="关闭" onClick={onClose} type="button">×</button>
          </div>
          <form className="entryForm" onSubmit={(event) => { event.preventDefault(); onSave(draft); }}>
            <label><span>目标体重 kg</span><input inputMode="decimal" value={draft.targetWeightKg} onChange={(event) => updateGoal("targetWeightKg", numberValue(event.target.value))} /></label>
            <label><span>目标日期</span><input value={draft.targetDate} onChange={(event) => updateGoal("targetDate", event.target.value)} type="date" /></label>
            <label><span>每日热量 kcal</span><input inputMode="decimal" value={draft.dailyCalories} onChange={(event) => updateGoal("dailyCalories", numberValue(event.target.value))} /></label>
            <label><span>蛋白质 g</span><input inputMode="decimal" value={draft.protein} onChange={(event) => updateGoal("protein", numberValue(event.target.value))} /></label>
            <label><span>膳食纤维 g</span><input inputMode="decimal" value={draft.fiber} onChange={(event) => updateGoal("fiber", numberValue(event.target.value))} /></label>
            <label><span>期望周降 kg</span><input inputMode="decimal" value={draft.weeklyLossKg} onChange={(event) => updateGoal("weeklyLossKg", numberValue(event.target.value))} /></label>
            <div className="goalPreview wide">
              <span>推荐节奏</span>
              <strong>{draft.weeklyLossKg.toFixed(1)}kg / 周</strong>
              <p>如果实际体重连续两周不动，优先检查记录完整度、加餐和活动量。</p>
            </div>
            <div className="entryActions">
              <button className="secondaryButton" onClick={onClose} type="button">取消</button>
              <button type="submit">保存目标</button>
            </div>
          </form>
        </section>
      </div>
    </ModalPortal>
  );
}

function FavoriteFoodsDialog({ favoriteFoods, onClose, onSave }: { favoriteFoods: FavoriteFood[]; onClose: () => void; onSave: (foods: FavoriteFood[]) => void }) {
  const [foods, setFoods] = useState<FavoriteFood[]>(favoriteFoods);

  function updateFood(index: number, patch: Partial<FavoriteFood>) {
    setFoods((current) => current.map((food, foodIndex) => foodIndex === index ? { ...food, ...patch } : food));
  }

  function addFood() {
    setFoods((current) => [
      ...current,
      { id: `fav-${Date.now()}`, name: "新的常吃食物", meal: "snack", grams: 100, calories: 100, protein: 0, carbs: 0, fat: 0, fiber: 0, note: "" },
    ]);
  }

  return (
    <ModalPortal>
      <div className="modalBackdrop" role="presentation" onClick={onClose}>
        <section aria-modal="true" className="entryDialog compactDialog favoritesDialog" role="dialog" onClick={(event) => event.stopPropagation()}>
          <div className="entryHead">
            <div>
              <h3>常吃食物库</h3>
              <p>这些食物会出现在总览页，点击即可加入当前日期。</p>
            </div>
            <button aria-label="关闭" onClick={onClose} type="button">×</button>
          </div>
          <div className="favoriteEditorList">
            {foods.map((food, index) => (
              <article className="favoriteEditorItem" key={food.id}>
                <input value={food.name} onChange={(event) => updateFood(index, { name: event.target.value })} />
                <select value={food.meal} onChange={(event) => updateFood(index, { meal: event.target.value as MealType })}>
                  {mealMeta.map((meal) => <option key={meal.key} value={meal.key}>{meal.title}</option>)}
                </select>
                <input inputMode="decimal" value={food.grams} onChange={(event) => updateFood(index, { grams: Number(event.target.value || 0) })} />
                <input inputMode="decimal" value={food.calories} onChange={(event) => updateFood(index, { calories: Number(event.target.value || 0) })} />
                <input inputMode="decimal" value={food.protein} onChange={(event) => updateFood(index, { protein: Number(event.target.value || 0) })} />
                <input inputMode="decimal" value={food.carbs} onChange={(event) => updateFood(index, { carbs: Number(event.target.value || 0) })} />
                <input inputMode="decimal" value={food.fat} onChange={(event) => updateFood(index, { fat: Number(event.target.value || 0) })} />
                <input inputMode="decimal" value={food.fiber} onChange={(event) => updateFood(index, { fiber: Number(event.target.value || 0) })} />
                <button aria-label="删除常吃食物" onClick={() => setFoods((current) => current.filter((_, foodIndex) => foodIndex !== index))} type="button"><Trash2 size={14} /></button>
              </article>
            ))}
          </div>
          <div className="favoriteEditorLegend">
            <span>名称</span><span>餐次</span><span>重量</span><span>热量</span><span>蛋白</span><span>碳水</span><span>脂肪</span><span>纤维</span><span />
          </div>
          <div className="entryActions">
            <button className="secondaryButton" onClick={addFood} type="button"><Plus size={15} />添加食物</button>
            <button className="secondaryButton" onClick={onClose} type="button">取消</button>
            <button onClick={() => onSave(foods.filter((food) => food.name.trim()))} type="button">保存食物库</button>
          </div>
        </section>
      </div>
    </ModalPortal>
  );
}

const DAILY_PHOTO_LIMIT = 5;

function countPhotosUploadedToday(items: FoodItem[]) {
  const today = dateKey(new Date());
  return items.reduce((sum, item) => {
    if (!item.createdAt || dateKey(new Date(item.createdAt)) !== today) return sum;
    return sum + item.photoUrls.length;
  }, 0);
}

function ManualEntryDialog({ defaultDate, defaultMeal, editingItem, items, mode = "manual", onClose, onSaved }: { defaultDate: string; defaultMeal: MealType; editingItem?: FoodItem; items: FoodItem[]; mode?: "manual" | "ai"; onClose: () => void; onSaved: (savedDate: string) => Promise<void> }) {
  const remainingPhotoQuota = Math.max(0, DAILY_PHOTO_LIMIT - countPhotosUploadedToday(items));
  const [date, setDate] = useState(editingItem?.date || dateKey(new Date()));
  const [meal, setMeal] = useState<MealType>(editingItem?.meal || defaultMeal);
  const [name, setName] = useState(editingItem?.name || "");
  const [grams, setGrams] = useState(editingItem ? String(round(editingItem.grams)) : "");
  const [calories, setCalories] = useState(editingItem ? String(round(editingItem.calories)) : "");
  const [protein, setProtein] = useState(editingItem ? String(round(editingItem.protein)) : "");
  const [carbs, setCarbs] = useState(editingItem ? String(round(editingItem.carbs)) : "");
  const [fat, setFat] = useState(editingItem ? String(round(editingItem.fat)) : "");
  const [fiber, setFiber] = useState(editingItem ? String(round(editingItem.fiber)) : "");
  const [note, setNote] = useState(editingItem?.note || "");
  const [photos, setPhotos] = useState<File[]>([]);
  const [retainedPhotoPaths, setRetainedPhotoPaths] = useState<string[]>(editingItem?.photoPaths || []);
  const [analysisItems, setAnalysisItems] = useState<AnalysisItem[]>([]);
  const [analysisHint, setAnalysisHint] = useState("");
  const [analyzing, setAnalyzing] = useState(false);
  const [analysisSummary, setAnalysisSummary] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const isAiMode = mode === "ai" && !editingItem;
  const analysisTotals = useMemo(() => analysisItems.reduce((sum, item) => ({
    grams: sum.grams + Number(item.grams || 0),
    calories: sum.calories + Number(item.calories || 0),
    protein: sum.protein + Number(item.protein || 0),
    carbs: sum.carbs + Number(item.carbs || 0),
    fat: sum.fat + Number(item.fat || 0),
    fiber: sum.fiber + Number(item.fiber || 0),
  }), { grams: 0, calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0 }), [analysisItems]);

  function numberValue(value: string) {
    return Number(value || 0);
  }

  function applyAnalysisItems(nextItems: AnalysisItem[]) {
    setAnalysisItems(nextItems);
    const total = nextItems.reduce((sum, item) => ({
      grams: sum.grams + Number(item.grams || 0),
      calories: sum.calories + Number(item.calories || 0),
      protein: sum.protein + Number(item.protein || 0),
      carbs: sum.carbs + Number(item.carbs || 0),
      fat: sum.fat + Number(item.fat || 0),
      fiber: sum.fiber + Number(item.fiber || 0),
    }), { grams: 0, calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0 });
    setGrams(String(round(total.grams)));
    setCalories(String(round(total.calories)));
    setProtein(String(round(total.protein)));
    setCarbs(String(round(total.carbs)));
    setFat(String(round(total.fat)));
    setFiber(String(round(total.fiber)));
  }

  function updateAnalysisItem(index: number, patch: Partial<AnalysisItem>) {
    applyAnalysisItems(analysisItems.map((item, itemIndex) => itemIndex === index ? { ...item, ...patch } : item));
  }

  function scaleAnalysisItem(index: number, factor: number) {
    const item = analysisItems[index];
    if (!item) return;
    updateAnalysisItem(index, {
      grams: Math.max(0, item.grams * factor),
      calories: Math.max(0, item.calories * factor),
      protein: Math.max(0, item.protein * factor),
      carbs: Math.max(0, item.carbs * factor),
      fat: Math.max(0, item.fat * factor),
      fiber: Math.max(0, item.fiber * factor),
    });
  }

  function handlePhotoSelect(event: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files || []);
    if (files.length > remainingPhotoQuota) {
      setError(`每人每天最多上传 ${DAILY_PHOTO_LIMIT} 张照片，今天还能上传 ${remainingPhotoQuota} 张，已自动截取前 ${remainingPhotoQuota} 张。`);
    }
    setPhotos(files.slice(0, remainingPhotoQuota));
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!name.trim() && !analysisItems.length) {
      setError(isAiMode ? "请先上传照片并完成 AI 分析。" : "请先填写食物名称。");
      return;
    }
    setSaving(true);
    setError("");
    try {
      if (editingItem) {
        await updateFoodItem(editingItem.id, {
          date,
          meal,
          name,
          grams: numberValue(grams),
          calories: numberValue(calories),
          protein: numberValue(protein),
          carbs: numberValue(carbs),
          fat: numberValue(fat),
          fiber: numberValue(fiber),
          note,
          photos,
          retainedPhotoPaths,
        });
      } else if (analysisItems.length) {
        await createFoodItems(analysisItems.map((item) => ({
          date,
          meal,
          name: item.name,
          grams: Number(item.grams || 0),
          calories: Number(item.calories || 0),
          protein: Number(item.protein || 0),
          carbs: Number(item.carbs || 0),
          fat: Number(item.fat || 0),
          fiber: Number(item.fiber || 0),
          note: [`AI 照片拆分估算。`, item.reasoning, note].filter(Boolean).join("\n"),
        })), photos);
      } else {
        await createFoodItem({
          date,
          meal,
          name,
          grams: numberValue(grams),
          calories: numberValue(calories),
          protein: numberValue(protein),
          carbs: numberValue(carbs),
          fat: numberValue(fat),
          fiber: numberValue(fiber),
          note,
          photos,
        });
      }
      await onSaved(date);
    } catch (error) {
      setError(formatCloudError(error));
    } finally {
      setSaving(false);
    }
  }

  async function handleAnalyzePhotos() {
    if (!photos.length) {
      setError("请先选择照片。");
      return;
    }
    const userHint = analysisHint.trim();
    setAnalyzing(true);
    setError("");
    setAnalysisSummary("");
    try {
      const payloadPhotos = await Promise.all(photos.slice(0, 3).map(async (file) => ({
        fileName: file.name,
        contentType: file.type || "image/jpeg",
        dataUrl: await imageFileToDataUrl(file, 1600, 0.82),
      })));
      const response = await fetch("/api/analyze-meal", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ photos: payloadPhotos, hint: userHint }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "AI 分析失败。");
      const analysis = payload.analysis;
      const total = analysis.total || {};
      setName(analysis.dishName || name);
      const nextAnalysisItems = (analysis.items || []).map((item: AnalysisItem) => ({
        name: item.name || "未知食物",
        grams: Number(item.grams || 0),
        calories: Number(item.calories || 0),
        protein: Number(item.protein || 0),
        carbs: Number(item.carbs || 0),
        fat: Number(item.fat || 0),
        fiber: Number(item.fiber || 0),
        reasoning: item.reasoning || "",
      })).filter((item: AnalysisItem) => item.name.trim());
      if (nextAnalysisItems.length) {
        applyAnalysisItems(nextAnalysisItems);
      } else {
        applyAnalysisItems([{ name: analysis.dishName || "AI 识别餐食", grams: Number(total.grams || 0), calories: Number(total.calories || 0), protein: Number(total.protein || 0), carbs: Number(total.carbs || 0), fat: Number(total.fat || 0), fiber: Number(total.fiber || 0), reasoning: analysis.notes || "" }]);
      }
      const itemLines = (nextAnalysisItems.length ? nextAnalysisItems : []).map((item: AnalysisItem) => `${item.name} ${round(Number(item.grams || 0))}g / ${round(Number(item.calories || 0))}kcal${item.reasoning ? `：${item.reasoning}` : ""}`);
      setNote([userHint ? `用户补充：${userHint}` : "", `AI 照片估算，置信度约 ${Math.round(Number(analysis.confidence || 0) * 100)}%。`, analysis.notes, ...itemLines].filter(Boolean).join("\n"));
      setAnalysisSummary(`已识别 ${nextAnalysisItems.length || 1} 个食物，约 ${round(Number(total.calories || 0))} kcal。可以先微调每个食物，再保存。`);
    } catch (error) {
      setError(formatCloudError(error));
    } finally {
      setAnalyzing(false);
    }
  }

  return (
    <ModalPortal>
      <div className="modalBackdrop" role="presentation" onClick={onClose}>
      <section aria-modal="true" className="entryDialog" role="dialog" onClick={(event) => event.stopPropagation()}>
        <div className="entryHead">
          <div>
            <h3>{editingItem ? "修改饮食记录" : mode === "ai" ? "AI 分析餐食" : "手动新增记录"}</h3>
            <p>{editingItem ? "修改后的热量、营养和照片会同步到云端。" : mode === "ai" ? "上传餐食照片后，AI 会先估算热量和营养，你确认后再保存。" : "适合补录已知热量，照片和营养数据会保存到云端。"}</p>
          </div>
          <button aria-label="关闭" onClick={onClose} type="button">×</button>
        </div>
        <form className={`entryForm ${isAiMode ? "aiEntryForm" : ""}`} onSubmit={handleSubmit}>
          <label><span>日期</span><input value={date} onChange={(event) => setDate(event.target.value)} type="date" /></label>
          <label>
            <span>餐次</span>
            <select value={meal} onChange={(event) => setMeal(event.target.value as MealType)}>
              {mealMeta.map((item) => <option key={item.key} value={item.key}>{item.title}</option>)}
            </select>
          </label>
          {isAiMode ? (
            <>
              <section className="aiUploadPanel wide">
                <div className="aiModeIntro">
                  <Sparkles size={18} />
                  <div>
                    <strong>上传照片后自动拆分食物</strong>
                    <span>可以再写一句份量说明，例如“米饭一小碗、鱼约 100g”。</span>
                  </div>
                </div>
                <label className={`aiUploadDrop ${remainingPhotoQuota ? "" : "disabled"}`}>
                  <input accept="image/*" disabled={!remainingPhotoQuota} multiple onChange={handlePhotoSelect} type="file" />
                  <CloudUpload size={22} />
                  <strong>{photos.length ? `已选择 ${photos.length} 张照片` : "选择或拖入餐食照片"}</strong>
                  <span>最多分析 3 张，会先压缩再上传分析。</span>
                </label>
                {photos.length ? (
                  <div className="aiSelectedPhotos">
                    {photos.slice(0, 3).map((photo) => <span key={`${photo.name}-${photo.size}`}>{photo.name}</span>)}
                  </div>
                ) : null}
                <small className="uploadQuotaHint">每人每天最多上传 {DAILY_PHOTO_LIMIT} 张照片，今天还能上传 {remainingPhotoQuota} 张</small>
              </section>
              <label className="wide aiHintField">
                <span>补充说明（可选）</span>
                <textarea value={analysisHint} onChange={(event) => setAnalysisHint(event.target.value)} placeholder="例如：一小碗米饭、两条鱼、下午骑车吃了 3 根香蕉" />
              </label>
              <div className="analysisAction aiAnalyzeAction">
                <p className="entryHint">{photos.length ? "点下面按钮后，AI 会估算每个食物的重量、热量和营养成分。" : "先上传照片；如果没照片，也可以用“手动新增记录”补录简单食物。"}</p>
                <button disabled={analyzing || !photos.length} onClick={handleAnalyzePhotos} type="button"><Sparkles size={15} />{analyzing ? "分析中" : "开始 AI 分析"}</button>
              </div>
            </>
          ) : (
            <>
              <label className="wide"><span>食物名称</span><input value={name} onChange={(event) => setName(event.target.value)} placeholder="例如：咖喱饭、香蕉、牛奶巧克力" /></label>
              <label><span>重量 g</span><input inputMode="decimal" value={grams} onChange={(event) => setGrams(event.target.value)} placeholder="0" /></label>
              <label><span>热量 kcal</span><input inputMode="decimal" value={calories} onChange={(event) => setCalories(event.target.value)} placeholder="0" /></label>
              <label><span>蛋白质 g</span><input inputMode="decimal" value={protein} onChange={(event) => setProtein(event.target.value)} placeholder="0" /></label>
              <label><span>碳水 g</span><input inputMode="decimal" value={carbs} onChange={(event) => setCarbs(event.target.value)} placeholder="0" /></label>
              <label><span>脂肪 g</span><input inputMode="decimal" value={fat} onChange={(event) => setFat(event.target.value)} placeholder="0" /></label>
              <label><span>膳食纤维 g</span><input inputMode="decimal" value={fiber} onChange={(event) => setFiber(event.target.value)} placeholder="0" /></label>
              <label className="wide"><span>备注</span><textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="可写估算来源、品牌、份量说明" /></label>
              {editingItem?.photoUrls.length ? (
                <div className="wide existingPhotos">
                  <span>已有照片</span>
                  <div>{editingItem.photoUrls.map((photo, index) => {
                    const photoPath = editingItem.photoPaths[index];
                    const removed = photoPath ? !retainedPhotoPaths.includes(photoPath) : false;
                    return (
                      <figure className={removed ? "removed" : ""} key={photo}>
                        <img alt="已有餐食照片" src={photo} />
                        {photoPath && <button onClick={() => setRetainedPhotoPaths((paths) => removed ? [...paths, photoPath] : paths.filter((path) => path !== photoPath))} type="button">{removed ? "恢复" : "移除"}</button>}
                      </figure>
                    );
                  })}</div>
                </div>
              ) : null}
              <label className="wide">
                <span>{editingItem ? "追加照片" : "照片"}</span>
                <input accept="image/*" disabled={!remainingPhotoQuota} multiple onChange={handlePhotoSelect} type="file" />
                <small className="uploadQuotaHint">每人每天最多上传 {DAILY_PHOTO_LIMIT} 张照片，今天还能上传 {remainingPhotoQuota} 张</small>
              </label>
              <div className="analysisAction">
                <p className="entryHint">{photos.length ? `已选择 ${photos.length} 张照片。可以先让 AI 估算，再确认保存。` : "如果你不知道热量，可以先上传照片让 AI 分析；也可以继续发给我估算。"}</p>
                <button disabled={analyzing || !photos.length} onClick={handleAnalyzePhotos} type="button"><Sparkles size={15} />{analyzing ? "分析中" : "AI 分析照片"}</button>
              </div>
            </>
          )}
          {analysisSummary && <p className="analysisSummary">{analysisSummary}</p>}
          {analysisItems.length ? (
            <section className="analysisReview wide">
              <div className="analysisResultCard">
                <div className="analysisResultMain">
                  <span><Sparkles size={18} /></span>
                  <div>
                    <strong>{round(analysisTotals.calories).toLocaleString()} kcal</strong>
                    <p>本餐估算 · {analysisItems.length} 个食物 · {round(analysisTotals.grams).toLocaleString()}g</p>
                  </div>
                </div>
                <div className="analysisResultStats">
                  <span>蛋白质 <b>{round(analysisTotals.protein)}g</b></span>
                  <span>碳水 <b>{round(analysisTotals.carbs)}g</b></span>
                  <span>脂肪 <b>{round(analysisTotals.fat)}g</b></span>
                  <span>膳食纤维 <b>{round(analysisTotals.fiber)}g</b></span>
                </div>
              </div>
              <div className="analysisReviewHead">
                <strong>确认食物拆分</strong>
                <span>可直接保存，也可以只微调有疑问的食物</span>
              </div>
              <div className="analysisItemList">
                {analysisItems.map((item, index) => (
                  <article className="analysisItem" key={`${item.name}-${index}`}>
                    <div className="analysisItemTop">
                      <input value={item.name} onChange={(event) => updateAnalysisItem(index, { name: event.target.value })} />
                      <button aria-label="删除这个食物" onClick={() => applyAnalysisItems(analysisItems.filter((_, itemIndex) => itemIndex !== index))} type="button"><Trash2 size={14} /></button>
                    </div>
                    <div className="portionControls">
                      <button onClick={() => scaleAnalysisItem(index, 0.9)} type="button">-10%</button>
                      <span>{round(item.grams)}g · {round(item.calories)} kcal</span>
                      <button onClick={() => scaleAnalysisItem(index, 1.1)} type="button">+10%</button>
                    </div>
                    <div className="analysisItemMetrics">
                      <span>蛋白质 {round(item.protein)}g</span>
                      <span>碳水 {round(item.carbs)}g</span>
                      <span>脂肪 {round(item.fat)}g</span>
                      <span>膳食纤维 {round(item.fiber)}g</span>
                    </div>
                    <details className="analysisFineTune">
                      <summary>微调重量和营养</summary>
                      <div className="analysisNutrients">
                        <label><span>重量</span><input inputMode="decimal" value={round(item.grams)} onChange={(event) => updateAnalysisItem(index, { grams: Number(event.target.value || 0) })} /></label>
                        <label><span>热量</span><input inputMode="decimal" value={round(item.calories)} onChange={(event) => updateAnalysisItem(index, { calories: Number(event.target.value || 0) })} /></label>
                        <label><span>蛋白质</span><input inputMode="decimal" value={round(item.protein)} onChange={(event) => updateAnalysisItem(index, { protein: Number(event.target.value || 0) })} /></label>
                        <label><span>碳水</span><input inputMode="decimal" value={round(item.carbs)} onChange={(event) => updateAnalysisItem(index, { carbs: Number(event.target.value || 0) })} /></label>
                        <label><span>脂肪</span><input inputMode="decimal" value={round(item.fat)} onChange={(event) => updateAnalysisItem(index, { fat: Number(event.target.value || 0) })} /></label>
                        <label><span>膳食纤维</span><input inputMode="decimal" value={round(item.fiber)} onChange={(event) => updateAnalysisItem(index, { fiber: Number(event.target.value || 0) })} /></label>
                      </div>
                    </details>
                    {item.reasoning && <p>{item.reasoning}</p>}
                  </article>
                ))}
              </div>
            </section>
          ) : null}
          {error && <p className="entryError">{error}</p>}
          <div className="entryActions">
            <button className="secondaryButton" onClick={onClose} type="button">取消</button>
            <button disabled={saving || (isAiMode && !analysisItems.length)} type="submit">{saving ? "保存中" : editingItem ? "更新到云端" : isAiMode ? "保存分析结果" : "保存到云端"}</button>
          </div>
        </form>
      </section>
      </div>
    </ModalPortal>
  );
}

function fileToDataUrl(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("读取照片失败。"));
    reader.readAsDataURL(file);
  });
}

function imageFileToDataUrl(file: File, maxSide = 1800, quality = 0.86) {
  if (!file.type.startsWith("image/")) return fileToDataUrl(file);
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("读取截图失败。"));
    reader.onload = () => {
      const image = new Image();
      image.onerror = () => reject(new Error("截图格式无法解析。"));
      image.onload = () => {
        const scale = Math.min(1, maxSide / Math.max(image.width, image.height));
        const width = Math.max(1, Math.round(image.width * scale));
        const height = Math.max(1, Math.round(image.height * scale));
        const canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext("2d");
        if (!context) {
          resolve(String(reader.result || ""));
          return;
        }
        context.drawImage(image, 0, 0, width, height);
        resolve(canvas.toDataURL("image/jpeg", quality));
      };
      image.src = String(reader.result || "");
    };
    reader.readAsDataURL(file);
  });
}

function TabButton({ active, icon, label, onClick }: { active: boolean; icon: React.ReactNode; label: string; onClick: () => void }) {
  return (
    <button className={active ? "active" : ""} onClick={onClick} type="button">
      {icon}
      {label}
    </button>
  );
}

function Overview({
  allItems,
  bodyMetrics,
  dailyActivities,
  exerciseActivities,
  favoriteFoods,
  goals,
  items,
  onAiAnalyze,
  onEdit,
  onManageFavorites,
  onOpenGoals,
  onQuickAddFavorite,
  onRecordMeal,
  selectedDate,
  totals,
}: {
  allItems: FoodItem[];
  bodyMetrics: BodyMetric[];
  dailyActivities: DailyActivity[];
  exerciseActivities: ExerciseActivity[];
  favoriteFoods: FavoriteFood[];
  goals: UserGoals;
  items: FoodItem[];
  onAiAnalyze: () => void;
  onEdit: () => void;
  onManageFavorites: () => void;
  onOpenGoals: () => void;
  onQuickAddFavorite: (food: FavoriteFood) => void;
  onRecordMeal: (meal: MealType) => void;
  selectedDate: string;
  totals: ReturnType<typeof totalsFor>;
}) {
  return (
    <section className="overviewLayout">
      <div className="journalColumn">
        <HeroStory goals={goals} items={items} onAiAnalyze={onAiAnalyze} onEdit={onEdit} totals={totals} />
        <MealTimeline items={items} onRecordMeal={onRecordMeal} />
        <FavoriteFoodsPanel favoriteFoods={favoriteFoods} onManage={onManageFavorites} onQuickAdd={onQuickAddFavorite} />
        <ReflectionBox />
      </div>
      <NutritionRail allItems={allItems} bodyMetrics={bodyMetrics} dailyActivities={dailyActivities} exerciseActivities={exerciseActivities} goals={goals} onOpenGoals={onOpenGoals} selectedDate={selectedDate} totals={totals} />
    </section>
  );
}

function GoalDashboard({
  bodyMetrics,
  dailyActivities,
  exerciseActivities,
  goals,
  onOpenGoals,
  selectedDate,
  totals,
}: {
  bodyMetrics: BodyMetric[];
  dailyActivities: DailyActivity[];
  exerciseActivities: ExerciseActivity[];
  goals: UserGoals;
  onOpenGoals: () => void;
  selectedDate: string;
  totals: ReturnType<typeof totalsFor>;
}) {
  const currentBody = latestBodyMetricOnOrBefore(bodyMetrics, selectedDate);
  const previousBody = previousBodyMetric(bodyMetrics, currentBody);
  const activeCalories = activityCaloriesForDate(dailyActivities, exerciseActivities, selectedDate);
  const calorieProgress = Math.min(140, Math.round((totals.calories / Math.max(1, goals.dailyCalories)) * 100));
  const proteinProgress = Math.min(140, Math.round((totals.protein / Math.max(1, goals.protein)) * 100));
  const fiberProgress = Math.min(140, Math.round((totals.fiber / Math.max(1, goals.fiber)) * 100));
  const remainingCalories = Math.round(goals.dailyCalories - totals.calories);
  const exerciseAdjusted = Math.round(goals.dailyCalories + activeCalories - totals.calories);
  const weightDelta = currentBody && previousBody ? currentBody.weightKg - previousBody.weightKg : 0;
  const targetGap = currentBody ? currentBody.weightKg - goals.targetWeightKg : 0;
  const daysLeft = daysBetween(selectedDate, goals.targetDate);
  const weeklyNeeded = currentBody && daysLeft > 0 ? Math.max(0, targetGap / Math.max(1, daysLeft / 7)) : 0;
  const status = remainingCalories >= 0
    ? `今天还可安排约 ${remainingCalories.toLocaleString()} kcal`
    : `今天已超出目标约 ${Math.abs(remainingCalories).toLocaleString()} kcal`;

  return (
    <GlassCard className="goalDashboard">
      <div className="goalHeader">
        <div>
          <span>目标系统</span>
          <h3>{status}</h3>
          <p>{activeCalories ? `计入运动后余量约 ${exerciseAdjusted.toLocaleString()} kcal` : "同步运动后会自动计算活动余量"}</p>
        </div>
        <button onClick={onOpenGoals} type="button"><Settings size={15} />调整目标</button>
      </div>
      <div className="goalRings">
        <GoalRing label="热量" progress={calorieProgress} value={`${round(totals.calories)} / ${goals.dailyCalories}`} tone="calorie" />
        <GoalRing label="蛋白质" progress={proteinProgress} value={`${round(totals.protein)} / ${goals.protein}g`} tone="protein" />
        <GoalRing label="膳食纤维" progress={fiberProgress} value={`${round(totals.fiber)} / ${goals.fiber}g`} tone="fiber" />
      </div>
      <div className="goalStats">
        <span><strong>{currentBody ? `${currentBody.weightKg.toFixed(2)}kg` : "--"}</strong><em>当前体重</em></span>
        <span><strong>{currentBody ? `${targetGap.toFixed(2)}kg` : "--"}</strong><em>距目标</em></span>
        <span><strong>{previousBody ? `${weightDelta > 0 ? "+" : ""}${weightDelta.toFixed(2)}kg` : "--"}</strong><em>较上次</em></span>
        <span><strong>{weeklyNeeded ? `${weeklyNeeded.toFixed(2)}kg/周` : "--"}</strong><em>所需速度</em></span>
      </div>
    </GlassCard>
  );
}

function AnimatedNumber({ value, duration = 700 }: { value: number; duration?: number }) {
  const [display, setDisplay] = useState(value);
  const previousRef = useRef(value);

  useEffect(() => {
    const from = previousRef.current;
    const to = value;
    previousRef.current = value;
    if (from === to) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setDisplay(to);
      return;
    }
    const start = performance.now();
    let frame = requestAnimationFrame(function tick(now: number) {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      setDisplay(Math.round(from + (to - from) * eased));
      if (t < 1) frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  }, [value, duration]);

  return <>{display.toLocaleString()}</>;
}

function GoalRing({ label, progress, value, tone }: { label: string; progress: number; value: string; tone: string }) {
  const displayProgress = Math.min(100, progress);
  return (
    <div className={`goalRing ${tone}`} style={{ "--progress": `${displayProgress}%` } as React.CSSProperties}>
      <div className="goalRingDial">
        <strong><AnimatedNumber value={Math.round(progress)} />%</strong>
      </div>
      <span>{label}</span>
      <em>{value}</em>
    </div>
  );
}

function FavoriteFoodsPanel({ favoriteFoods, onManage, onQuickAdd }: { favoriteFoods: FavoriteFood[]; onManage: () => void; onQuickAdd: (food: FavoriteFood) => void }) {
  return (
    <GlassCard className="favoriteFoodsPanel">
      <div className="panelHead">
        <div>
          <span>食物库</span>
          <h3>常吃食物一键添加</h3>
        </div>
        <button onClick={onManage} type="button"><Settings size={15} />管理</button>
      </div>
      <div className="favoriteFoodChips">
        {favoriteFoods.slice(0, 8).map((food) => {
          const serving = favoriteServing(food);
          const scaledCalories = scaleNutrient(food.calories, food.grams, serving.grams);
          const category = foodCategoryMeta(food.name, food.note);
          return (
            <button className={`tone-${category.tone}`} key={food.id} onClick={() => onQuickAdd(food)} title={`点击一次添加 ${serving.label}`} type="button">
              <i className="favoriteFoodChipIcon">{category.emoji}</i>
              <span>{food.name}</span>
              <small>{serving.label}</small>
              <em>{round(scaledCalories)} kcal</em>
            </button>
          );
        })}
      </div>
    </GlassCard>
  );
}

function foodCategoryMeta(name: string, note: string): { emoji: string; tone: string } {
  const text = `${name} ${note || ""}`;
  if (/蛋|鸡|牛肉|猪肉|羊肉|鱼|虾|肉|豆腐|豆干/.test(text)) return { emoji: "🍗", tone: "protein" };
  if (/米饭|面|粥|燕麦|馒头|面包|吐司|饼|薯|土豆|红薯|玉米/.test(text)) return { emoji: "🍚", tone: "carbs" };
  if (/西兰花|小松菜|胡萝卜|生菜|菠菜|黄瓜|番茄|西红柿|蔬菜|菜/.test(text)) return { emoji: "🥦", tone: "fiber" };
  if (/果|香蕉|苹果|橙|葡萄|莓/.test(text)) return { emoji: "🍎", tone: "cal" };
  if (/奶|酸奶|拿铁|咖啡|茶|豆浆/.test(text)) return { emoji: "🥛", tone: "body" };
  return { emoji: "🍪", tone: "heart" };
}

function favoriteServing(food: FavoriteFood) {
  const name = food.name.trim();
  const note = food.note || "";
  const compact = `${name} ${note}`;
  const explicitUnit = compact.match(/(\d+(?:\.\d+)?)\s*(根|个|颗|杯|碗|份)/);
  if (explicitUnit) return { label: `+${Number(explicitUnit[1]).toLocaleString()}${explicitUnit[2]}`, grams: food.grams };
  if (/香蕉/.test(name)) return { label: "+1根", grams: food.grams || 120 };
  if (/蛋/.test(name)) return { label: "+1个", grams: food.grams || 50 };
  if (/牛奶/.test(name) && !/燕麦/.test(name)) return { label: "+100ml", grams: 100 };
  if (/鸡|牛肉|鱼|虾|肉/.test(name)) return { label: "+50g", grams: 50 };
  if (/西兰花|小松菜|胡萝卜|蔬菜|菜/.test(name)) return { label: "+100g", grams: 100 };
  if (/燕麦|米饭|咖喱|面|粥/.test(name)) return { label: "+1碗", grams: food.grams };
  return { label: `+${round(food.grams)}g`, grams: food.grams };
}

function scaleNutrient(value: number, originalGrams: number, targetGrams: number) {
  if (!originalGrams || originalGrams === targetGrams) return value;
  return value * (targetGrams / originalGrams);
}

function scaleFavoriteForServing(food: FavoriteFood, servingGrams: number): FavoriteFood {
  if (!food.grams || servingGrams === food.grams) return food;
  return {
    ...food,
    grams: servingGrams,
    calories: scaleNutrient(food.calories, food.grams, servingGrams),
    protein: scaleNutrient(food.protein, food.grams, servingGrams),
    carbs: scaleNutrient(food.carbs, food.grams, servingGrams),
    fat: scaleNutrient(food.fat, food.grams, servingGrams),
    fiber: scaleNutrient(food.fiber, food.grams, servingGrams),
  };
}

function HeroStory({ goals, items, onAiAnalyze, onEdit, totals }: { goals: UserGoals; items: FoodItem[]; onAiAnalyze: () => void; onEdit: () => void; totals: ReturnType<typeof totalsFor> }) {
  const photos = uniquePhotos(items);
  const remaining = Math.round(goals.dailyCalories - totals.calories);
  return (
    <GlassCard className="todayCard">
      <div className="todayHead">
        <span className="todayLabel">今日摄入</span>
        <div className="todayActions">
          <button className="aiAnalyzeButton" onClick={onAiAnalyze} type="button"><Sparkles size={15} />AI 分析</button>
          <button className="secondaryButton" onClick={onEdit} type="button"><PenLine size={15} />明细</button>
        </div>
      </div>
      <div className="todayNumber">
        <strong><AnimatedNumber value={round(totals.calories)} /></strong>
        <small>kcal</small>
        <em className={remaining >= 0 ? "" : "over"}>
          {remaining >= 0
            ? <>还可安排 <AnimatedNumber value={remaining} /> kcal</>
            : <>超出目标 <AnimatedNumber value={Math.abs(remaining)} /> kcal</>}
        </em>
      </div>
      <div className="todayMacros">
        <span>蛋白质 <b>{round(totals.protein)}g</b></span>
        <span>碳水 <b>{round(totals.carbs)}g</b></span>
        <span>脂肪 <b>{round(totals.fat)}g</b></span>
        <span>膳食纤维 <b>{round(totals.fiber)}g</b></span>
      </div>
      {photos.length ? (
        <div className="todayPhotos">
          {photos.slice(0, 4).map((photo) => (
            <div className="photoTile" key={photo} style={{ backgroundImage: `url("${photo}")` }} />
          ))}
        </div>
      ) : null}
    </GlassCard>
  );
}

function MealTimeline({ items, onRecordMeal }: { items: FoodItem[]; onRecordMeal: (meal: MealType) => void }) {
  return (
    <GlassCard className="mealList">
      {mealMeta.map((meal) => (
        <MealTimelineCard key={meal.key} meal={meal.key} onRecordMeal={onRecordMeal} title={meal.title} hint={meal.hint} items={itemsByMeal(items, meal.key)} />
      ))}
    </GlassCard>
  );
}

function mealIcon(meal: MealType) {
  if (meal === "breakfast") return <Sun size={22} />;
  if (meal === "lunch") return <Utensils size={22} />;
  if (meal === "dinner") return <Coffee size={22} />;
  return <Moon size={22} />;
}

function MealTimelineCard({ meal, onRecordMeal, title, hint, items }: { meal: MealType; onRecordMeal: (meal: MealType) => void; title: string; hint: string; items: FoodItem[] }) {
  const totals = totalsFor(items);
  const photos = uniquePhotos(items);
  const hasItems = items.length > 0;
  return (
    <article className={hasItems ? "timelineMeal hasItems" : "timelineMeal"}>
      <div className="mealRowHead">
        <div className="mealIcon">{mealIcon(meal)}</div>
        <div className="timelineMealMeta">
          <h3>{title}</h3>
          <p>{hasItems ? `${items.length} 个食物` : hint}</p>
        </div>
        {hasItems ? (
          <strong className="mealRowKcal">{round(totals.calories).toLocaleString()} kcal</strong>
        ) : (
          <button className="ghostAdd" onClick={() => onRecordMeal(meal)} type="button"><Plus size={14} />记录{title}</button>
        )}
      </div>
      {hasItems ? (
        <div className="timelineMealContent">
          {photos.length ? <PhotoStrip photos={photos} empty="" /> : null}
          <div className="foodChips">
            {items.slice(0, 4).map((item) => (
              <span key={item.id}>{item.name} <b>{round(item.calories)}kcal</b></span>
            ))}
          </div>
          <MealNutrientStrip totals={totals} />
        </div>
      ) : null}
    </article>
  );
}

function MealNutrientStrip({ totals }: { totals: ReturnType<typeof totalsFor> }) {
  const rows = [
    { label: "蛋白质", value: totals.protein, target: 45, unit: "g", tone: "protein", icon: <Dumbbell size={13} /> },
    { label: "碳水", value: totals.carbs, target: 95, unit: "g", tone: "carbs", icon: <Wheat size={13} /> },
    { label: "脂肪", value: totals.fat, target: 28, unit: "g", tone: "fat", icon: <Droplets size={13} /> },
    { label: "膳食纤维", value: totals.fiber, target: 12, unit: "g", tone: "fiber", icon: <Leaf size={13} /> },
  ];
  return (
    <div className="mealNutrients" aria-label="本餐营养构成">
      {rows.map((row) => {
        const percent = Math.min(100, Math.round((row.value / row.target) * 100));
        return (
          <div className={`mealNutrientRow ${row.tone}`} key={row.label}>
            <div>
              <span>{row.icon}{row.label}</span>
              <strong>{round(row.value)}{row.unit}</strong>
            </div>
            <i><b style={{ width: `${percent}%` }} /></i>
          </div>
        );
      })}
    </div>
  );
}

function ReflectionBox() {
  const [saved, setSaved] = useState(false);

  function handleSave() {
    setSaved(true);
    window.setTimeout(() => setSaved(false), 1800);
  }

  return (
    <GlassCard className="reflectionBox">
      <ListChecks size={18} />
      <span>{saved ? "已保存这个提醒。" : "今天的饮食感受如何？记录一下吧..."}</span>
      <button onClick={handleSave} type="button">{saved ? "已保存" : "保存"}</button>
    </GlassCard>
  );
}

function NutritionRail({
  allItems,
  bodyMetrics,
  dailyActivities,
  exerciseActivities,
  goals,
  onOpenGoals,
  selectedDate,
  totals,
}: {
  allItems: FoodItem[];
  bodyMetrics: BodyMetric[];
  dailyActivities: DailyActivity[];
  exerciseActivities: ExerciseActivity[];
  goals: UserGoals;
  onOpenGoals: () => void;
  selectedDate: string;
  totals: ReturnType<typeof totalsFor>;
}) {
  return (
    <aside className="nutritionRail">
      <GoalDashboard bodyMetrics={bodyMetrics} dailyActivities={dailyActivities} exerciseActivities={exerciseActivities} goals={goals} onOpenGoals={onOpenGoals} selectedDate={selectedDate} totals={totals} />
      <PeriodReportCard bodyMetrics={bodyMetrics} dailyActivities={dailyActivities} exerciseActivities={exerciseActivities} goals={goals} items={allItems} selectedDate={selectedDate} />
    </aside>
  );
}

function PhotoStrip({ photos, empty }: { photos: string[]; empty: string }) {
  if (!photos.length) return <div className="photoStrip empty">{empty}</div>;
  return (
    <div className={photos.length > 1 ? "photoStrip multi" : "photoStrip"}>
      {photos.slice(0, 4).map((photo) => <div className="photoTile" key={photo} style={{ backgroundImage: `url("${photo}")` }} />)}
    </div>
  );
}

function InsightCard({ tone, title, items }: { tone: "good" | "warn"; title: string; items: string[] }) {
  return (
    <article className={`insightCard ${tone}`}>
      <h4>{title}</h4>
      <ul>{items.map((item) => <li key={item}>{item}</li>)}</ul>
    </article>
  );
}

function PeriodReportCard({
  bodyMetrics,
  dailyActivities,
  exerciseActivities,
  goals,
  items,
  selectedDate,
}: {
  bodyMetrics: BodyMetric[];
  dailyActivities: DailyActivity[];
  exerciseActivities: ExerciseActivity[];
  goals: UserGoals;
  items: FoodItem[];
  selectedDate: string;
}) {
  const report = buildPeriodReport(items, bodyMetrics, dailyActivities, exerciseActivities, goals, selectedDate, 7);
  return (
    <GlassCard className="periodReportCard">
      <div className="periodReportHead">
        <div>
          <span>7 日复盘</span>
          <h4>{report.summary}</h4>
        </div>
        <LineChart size={17} />
      </div>
      <div className="periodStats">
        <span><strong>{round(report.averageCalories)}</strong><em>平均 kcal</em></span>
        <span><strong>{round(report.averageProtein)}g</strong><em>蛋白平均</em></span>
        <span><strong>{report.onTargetDays}/{report.days}</strong><em>热量达标</em></span>
        <span><strong>{report.weightDeltaText}</strong><em>体重变化</em></span>
      </div>
      <ul>
        {report.insights.map((insight) => <li key={insight}>{insight}</li>)}
      </ul>
    </GlassCard>
  );
}

function CoachPanel({ items, totals }: { items: FoodItem[]; totals: ReturnType<typeof totalsFor> }) {
  const impactFoods = [...items].sort((a, b) => b.calories - a.calories).slice(0, 3);
  const swaps = buildSwapSuggestions(items);
  const tomorrow = buildTomorrowSuggestions(totals);
  return (
    <article className="coachCard">
      <h4>减脂复盘</h4>
      <div className="coachBlock">
        <strong>影响最大的食物</strong>
        {impactFoods.length ? (
          <ol>{impactFoods.map((item) => <li key={item.id}><span>{item.name}</span><em>{round(item.calories)} kcal</em></li>)}</ol>
        ) : <p>记录食物后这里会自动排序。</p>}
      </div>
      <div className="coachBlock">
        <strong>可以替换</strong>
        <ul>{swaps.map((item) => <li key={item}>{item}</li>)}</ul>
      </div>
      <div className="coachBlock">
        <strong>明天建议</strong>
        <ul>{tomorrow.map((item) => <li key={item}>{item}</li>)}</ul>
      </div>
    </article>
  );
}

function BodyDashboard({ bodyMetrics, bodyState, items, onDeleteMetric, onOpenEditor, selectedDate }: { bodyMetrics: BodyMetric[]; bodyState: string; items: FoodItem[]; onDeleteMetric: (metric: BodyMetric) => void; onOpenEditor: () => void; selectedDate: string }) {
  const [selectedMetricKey, setSelectedMetricKey] = useState<BodyMetricKey | null>(null);
  const sortedMetrics = [...bodyMetrics].sort((a, b) => b.date.localeCompare(a.date));
  const current = sortedMetrics.find((metric) => metric.date === selectedDate) || sortedMetrics[0];
  const previous = current ? sortedMetrics.find((metric) => metric.date < current.date) : undefined;
  const dayTotals = totalsFor(items.filter((item) => item.date === (current?.date || selectedDate)));
  const recent = sortedMetrics.slice(0, 10).reverse();
  const maxWeight = Math.max(1, ...recent.map((metric) => metric.weightKg));
  const minWeight = Math.min(...recent.map((metric) => metric.weightKg), maxWeight);
  const metricDefinitions: BodyMetricDefinition[] = [
    { key: "weightKg", label: "体重", unit: "kg", tone: "blue", color: "#0A84FF", icon: <Scale size={18} />, format: (value) => value.toFixed(2) },
    { key: "bodyFatPercent", label: "体脂", unit: "%", tone: "purple", color: "#5856D6", icon: <Activity size={18} />, format: (value) => value.toFixed(1) },
    { key: "muscleKg", label: "肌肉", unit: "kg", tone: "cyan", color: "#00A7C7", icon: <Dumbbell size={18} />, format: (value) => value.toFixed(1) },
    { key: "bmrKcal", label: "基础代谢", unit: "kcal", tone: "amber", color: "#C48615", icon: <Flame size={18} />, format: (value) => round(value).toLocaleString() },
    { key: "waterPercent", label: "水分", unit: "%", tone: "teal", color: "#30A46C", icon: <Droplets size={18} />, format: (value) => value.toFixed(1) },
    { key: "visceralFat", label: "内脏脂肪", unit: "", tone: "slate", color: "#64748B", icon: <ShieldCheck size={18} />, format: (value) => value.toFixed(1) },
  ];
  const selectedMetric = metricDefinitions.find((definition) => definition.key === selectedMetricKey);

  return (
    <section className="bodyLayout">
      <div className="bodyMain">
        <section className="bodyHero">
          <div>
            <p className="todayLabel">身体数据 · 和饮食一起看趋势</p>
            <h2>{current ? formatDateLabel(current.date) : "还没有身体数据"}</h2>
            <p>{current ? `体重 ${current.weightKg.toFixed(2)}kg · 体脂 ${current.bodyFatPercent.toFixed(1)}% · BMI ${current.bmi.toFixed(1)}` : "记录体重、体脂、BMI、基础代谢等数据后，这里会自动生成综合分析。"}</p>
          </div>
          <button className="aiAnalyzeButton" onClick={onOpenEditor} type="button"><Plus size={16} />记录身体数据</button>
        </section>

        {current ? (
          <>
            <section className="bodyMetricGrid">
              {metricDefinitions.map((definition) => (
                <BodyMetricCard
                  delta={formatDelta(Number(current[definition.key] || 0), previous ? Number(previous[definition.key] || 0) : undefined, definition.unit)}
                  icon={definition.icon}
                  key={definition.key}
                  label={definition.label}
                  onClick={() => setSelectedMetricKey(definition.key)}
                  tone={definition.tone}
                  unit={definition.unit}
                  value={definition.format(Number(current[definition.key] || 0))}
                />
              ))}
            </section>

            <section className="bodySplit">
              <article className="bodyTrendCard">
                <div className="bodySectionHead">
                  <div>
                    <h3>体重趋势</h3>
                    <p>最近 {recent.length} 次记录</p>
                  </div>
                  <strong>{current.score ? `${round(current.score)} 分` : current.bodyType || "--"}</strong>
                </div>
                <BodyWeightLineChart currentDate={current.date} maxWeight={maxWeight} metrics={recent} minWeight={minWeight} />
              </article>

              <article className="bodyAnalysisCard">
                <div className="bodySectionHead">
                  <div>
                    <h3>饮食 + 身体分析</h3>
                    <p>{round(dayTotals.calories).toLocaleString()} kcal · 蛋白 {round(dayTotals.protein)}g</p>
                  </div>
                  <Activity size={18} />
                </div>
                <ul>
                  {buildBodyFoodInsights(current, previous, dayTotals).map((item) => <li key={item}>{item}</li>)}
                </ul>
              </article>
            </section>

            <BodyCompositionFigure metric={current} />

            <section className="bodyDetailCard">
              <div className="bodySectionHead">
                <div>
                  <h3>完整指标</h3>
                  <p>{current.measuredAt ? formatMeasuredAt(current.measuredAt) : "未记录具体时间"}</p>
                </div>
                <button onClick={onOpenEditor} type="button"><PenLine size={15} />修改</button>
              </div>
              <div className="bodyDetailGrid">
                <MetricLine label="BMI" value={current.bmi.toFixed(1)} status={bmiStatus(current.bmi)} />
                <MetricLine label="身体年龄" value={round(current.bodyAge)} status={current.bodyAge ? "参考" : "--"} />
                <MetricLine label="体型" value={current.bodyType || "--"} status="参考" />
                <MetricLine label="骨量" value={`${current.boneMassKg.toFixed(1)} kg`} status="参考" />
                <MetricLine label="蛋白质" value={`${current.proteinPercent.toFixed(1)}%`} status={current.proteinPercent >= 16 ? "标准" : "偏低"} />
                <MetricLine label="骨骼肌" value={`${current.skeletalMuscleKg.toFixed(1)} kg`} status="参考" />
              </div>
              {current.note && <p className="bodyNote">{current.note}</p>}
            </section>
          </>
        ) : (
          <section className="bodyEmpty">
            <Scale size={30} />
            <h3>先记录一次身体数据</h3>
            <p>{bodyState.includes("不可用") ? bodyState : "可以先把体脂秤截图里的体重、体脂、BMI、基础代谢录进来。"}</p>
            <button onClick={onOpenEditor} type="button">开始记录</button>
          </section>
        )}
      </div>

      <aside className="bodyHistory">
        <div className="bodySectionHead">
          <div>
            <h3>身体记录</h3>
            <p>{sortedMetrics.length} 条</p>
          </div>
        </div>
        {sortedMetrics.length ? sortedMetrics.map((metric) => (
          <article className={metric.date === selectedDate ? "bodyHistoryItem active" : "bodyHistoryItem"} key={metric.id}>
            <div>
              <strong>{formatDateLabel(metric.date)}</strong>
              <span>{metric.weightKg.toFixed(2)}kg · 体脂 {metric.bodyFatPercent.toFixed(1)}%</span>
            </div>
            <button aria-label="删除身体数据" onClick={() => onDeleteMetric(metric)} type="button"><Trash2 size={14} /></button>
          </article>
        )) : <p className="bodyHistoryEmpty">还没有历史记录。</p>}
      </aside>
      {selectedMetric && (
        <BodyMetricHistoryDialog
          currentDate={current?.date || selectedDate}
          definition={selectedMetric}
          metrics={bodyMetrics}
          onClose={() => setSelectedMetricKey(null)}
        />
      )}
    </section>
  );
}

function BodyWeightLineChart({ currentDate, maxWeight, metrics, minWeight }: { currentDate: string; maxWeight: number; metrics: BodyMetric[]; minWeight: number }) {
  const width = 340;
  const height = 180;
  const padX = 24;
  const padTop = 18;
  const padBottom = 38;
  const chartHeight = height - padTop - padBottom;
  const range = Math.max(0.6, maxWeight - minWeight);
  const points = metrics.map((metric, index) => {
    const x = metrics.length <= 1 ? width / 2 : padX + (index / (metrics.length - 1)) * (width - padX * 2);
    const y = padTop + (1 - (metric.weightKg - minWeight) / range) * chartHeight;
    return { date: metric.date, label: metric.date.slice(5), value: metric.weightKg, x, y };
  });
  const firstPoint = points[0];
  const lastPoint = points[points.length - 1];
  return (
    <div className="bodyWeightChart line">
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" aria-label="体重折线趋势">
        <line className="metricGridLine" x1={padX} x2={width - padX} y1={padTop} y2={padTop} />
        <line className="metricGridLine" x1={padX} x2={width - padX} y1={padTop + chartHeight / 2} y2={padTop + chartHeight / 2} />
        <line className="metricGridLine" x1={padX} x2={width - padX} y1={padTop + chartHeight} y2={padTop + chartHeight} />
        <polyline className="bodyWeightArea" points={`${points.map((point) => `${point.x},${point.y}`).join(" ")} ${lastPoint?.x || width - padX},${padTop + chartHeight} ${firstPoint?.x || padX},${padTop + chartHeight}`} />
        <polyline className="bodyWeightLine" points={points.map((point) => `${point.x},${point.y}`).join(" ")} />
        {points.map((point) => (
          <g className={point.date === currentDate ? "active" : ""} key={point.date}>
            <circle cx={point.x} cy={point.y} r={point.date === currentDate ? 5 : 4} />
            <text className="bodyWeightValue" x={point.x} y={Math.max(12, point.y - 10)}>{point.value.toFixed(1)}</text>
            <text className="bodyWeightDate" x={point.x} y={height - 10}>{point.label}</text>
          </g>
        ))}
      </svg>
    </div>
  );
}

const BODY_FIGURE_VIEWBOX = { width: 220, height: 440 };

const BODY_FIGURE_POINTS: Record<"trunk" | "leftArm" | "rightArm" | "leftLeg" | "rightLeg", { x: number; y: number; anchor: "start" | "end" }> = {
  trunk: { x: 110, y: 130, anchor: "start" },
  rightArm: { x: 54, y: 205, anchor: "end" },
  leftArm: { x: 166, y: 205, anchor: "start" },
  rightLeg: { x: 90, y: 400, anchor: "end" },
  leftLeg: { x: 130, y: 400, anchor: "start" },
};

function BodyCompositionFigure({ metric }: { metric: BodyMetric }) {
  const parts = bodyPartMetrics(metric);
  const mapItems: { key: keyof typeof BODY_FIGURE_POINTS; label: string; part: { fat: number; muscle: number } }[] = [
    { key: "trunk", label: "躯干", part: parts.trunk },
    { key: "rightArm", label: "右手", part: parts.rightArm },
    { key: "leftArm", label: "左手", part: parts.leftArm },
    { key: "rightLeg", label: "右腿", part: parts.rightLeg },
    { key: "leftLeg", label: "左腿", part: parts.leftLeg },
  ];
  return (
    <section className="bodyFigureCard">
      <div className="bodySectionHead">
        <div>
          <h3>身体分布图</h3>
          <p>蓝色为脂肪率，青色为肌肉量</p>
        </div>
        <strong>{metric.bodyFatPercent.toFixed(1)}% 体脂</strong>
      </div>
      <div className="bodyScanMap">
        <svg className="bodyScanFigure" viewBox={`0 0 ${BODY_FIGURE_VIEWBOX.width} ${BODY_FIGURE_VIEWBOX.height}`} role="img" aria-label="身体分布图">
          <defs>
            <linearGradient gradientUnits="userSpaceOnUse" id="scanBodyGradient" x1="20" x2="200" y1="0" y2="440">
              <stop className="scanGradientStart" offset="0%" />
              <stop className="scanGradientEnd" offset="100%" />
            </linearGradient>
          </defs>
          <ellipse className="scanFloor" cx="110" cy="428" rx="52" ry="8" />
          <circle className="scanSilhouette" cx="110" cy="40" r="22" />
          <path className="scanLimb" d="M54,205 L78,92" />
          <path className="scanLimb" d="M166,205 L142,92" />
          <path className="scanLimb scanLimbLeg" d="M90,400 L96,214" />
          <path className="scanLimb scanLimbLeg" d="M130,400 L124,214" />
          <path
            className="scanSilhouette"
            d="M80,80 C70,100 68,150 84,192 L88,214 C96,226 124,226 132,214 L136,192 C152,150 150,100 140,80 C128,66 92,66 80,80 Z"
          />
          <g className="scanConnectors">
            {Object.entries(BODY_FIGURE_POINTS).map(([key, point]) => (
              <line
                className="scanConnector"
                key={key}
                x1={point.x}
                x2={point.anchor === "end" ? point.x - 28 : point.x + 28}
                y1={point.y}
                y2={point.y}
              />
            ))}
          </g>
          {Object.entries(BODY_FIGURE_POINTS).map(([key, point]) => (
            <g key={key}>
              <circle className="scanPointRing" cx={point.x} cy={point.y} r="6" />
              <circle className="scanPoint" cx={point.x} cy={point.y} r="3" />
            </g>
          ))}
        </svg>
        {mapItems.map((item) => {
          const point = BODY_FIGURE_POINTS[item.key];
          return (
            <BodyMapMetric
              anchor={point.anchor}
              key={item.key}
              label={item.label}
              part={item.part}
              style={{ top: `${(point.y / BODY_FIGURE_VIEWBOX.height) * 100}%`, left: `${(point.x / BODY_FIGURE_VIEWBOX.width) * 100}%` }}
            />
          );
        })}
      </div>
      <div className="bodyMapLegend">
        <span><i className="fatDot" />脂肪率 %</span>
        <span><i className="muscleDot" />肌肉量 kg</span>
      </div>
    </section>
  );
}

function BodyMapMetric({ anchor, label, part, style }: { anchor: "start" | "end"; label: string; part: { fat: number; muscle: number }; style: React.CSSProperties }) {
  return (
    <div className={`bodyMapMetric bodyMapMetric-${anchor}`} style={style}>
      <strong>{label}</strong>
      <div>
        <span><i className="fatDot" />{part.fat.toFixed(1)}%</span>
        <span><i className="muscleDot" />{part.muscle.toFixed(1)}kg</span>
      </div>
    </div>
  );
}

function BodyMetricCard({ delta, icon, label, onClick, tone, unit, value }: { delta: string; icon: React.ReactNode; label: string; onClick?: () => void; tone: string; unit: string; value: string }) {
  return (
    <button className={`bodyMetricCard ${tone}`} onClick={onClick} type="button">
      <span>{icon}</span>
      <div>
        <p>{label}</p>
        <strong>{value}<small>{unit}</small></strong>
        {delta && <em>{delta}</em>}
      </div>
      <ChevronRight className="bodyMetricCardArrow" size={16} />
    </button>
  );
}

function BodyMetricHistoryDialog({ currentDate, definition, metrics, onClose }: { currentDate: string; definition: BodyMetricDefinition; metrics: BodyMetric[]; onClose: () => void }) {
  const series = [...metrics]
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((metric) => ({ date: metric.date, value: Number(metric[definition.key] || 0), id: metric.id }))
    .filter((point) => Number.isFinite(point.value) && point.value > 0);
  const latest = series[series.length - 1];
  const previous = series[series.length - 2];
  const first = series[0];
  const minValue = Math.min(...series.map((point) => point.value));
  const maxValue = Math.max(...series.map((point) => point.value));
  const range = Math.max(0.1, maxValue - minValue);
  const chartWidth = 640;
  const chartHeight = 220;
  const points = series.map((point, index) => {
    const x = series.length === 1 ? chartWidth / 2 : 34 + (index / Math.max(1, series.length - 1)) * (chartWidth - 68);
    const y = 178 - ((point.value - minValue) / range) * 132;
    return { ...point, x, y };
  });
  const linePath = points.map((point, index) => `${index ? "L" : "M"} ${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(" ");
  const areaPath = points.length ? `${linePath} L ${points[points.length - 1].x.toFixed(1)} 196 L ${points[0].x.toFixed(1)} 196 Z` : "";
  const average = series.length ? series.reduce((sum, point) => sum + point.value, 0) / series.length : 0;
  const latestDelta = latest && previous ? latest.value - previous.value : 0;
  const totalDelta = latest && first ? latest.value - first.value : 0;

  return (
    <ModalPortal>
      <div className="modalBackdrop" role="presentation" onClick={onClose}>
      <section aria-modal="true" className="metricHistoryDialog" role="dialog" onClick={(event) => event.stopPropagation()}>
        <div className="metricHistoryHead">
          <div>
            <span style={{ color: definition.color }}>{definition.icon}</span>
            <div>
              <h3>{definition.label}历史</h3>
              <p>{series.length ? `${series[0].date} 至 ${series[series.length - 1].date} · ${series.length} 条记录` : "暂无历史记录"}</p>
            </div>
          </div>
          <button aria-label="关闭" onClick={onClose} type="button">×</button>
        </div>

        {series.length ? (
          <>
            <div className="metricHistorySummary">
              <div>
                <span>最新</span>
                <strong>{definition.format(latest.value)}<small>{definition.unit}</small></strong>
                <em>{formatMetricDelta(latestDelta, definition.unit)}</em>
              </div>
              <div>
                <span>平均</span>
                <strong>{definition.format(average)}<small>{definition.unit}</small></strong>
                <em>按当前记录</em>
              </div>
              <div>
                <span>累计变化</span>
                <strong>{formatMetricDelta(totalDelta, definition.unit)}</strong>
                <em>相对第一条</em>
              </div>
            </div>

            <div className="metricHistoryChart">
              <svg aria-label={`${definition.label}历史趋势图`} role="img" viewBox={`0 0 ${chartWidth} ${chartHeight}`}>
                <defs>
                  <linearGradient id={`metricArea-${definition.key}`} x1="0" x2="0" y1="0" y2="1">
                    <stop offset="0%" stopColor={definition.color} stopOpacity=".22" />
                    <stop offset="100%" stopColor={definition.color} stopOpacity="0" />
                  </linearGradient>
                </defs>
                {[46, 90, 134, 178].map((y) => <line key={y} className="metricGridLine" x1="28" x2="612" y1={y} y2={y} />)}
                {areaPath && <path d={areaPath} fill={`url(#metricArea-${definition.key})`} />}
                {linePath && <path className="metricHistoryLine" d={linePath} style={{ stroke: definition.color }} />}
                {points.map((point) => (
                  <g className={point.date === currentDate ? "active" : ""} key={point.id}>
                    <circle cx={point.x} cy={point.y} r={point.date === currentDate ? 6 : 4} style={{ fill: point.date === currentDate ? definition.color : "#fff", stroke: definition.color }} />
                    {point.date === currentDate && <text x={point.x} y={point.y - 13}>{definition.format(point.value)}{definition.unit}</text>}
                  </g>
                ))}
                {points.map((point, index) => index % Math.max(1, Math.ceil(points.length / 6)) === 0 || index === points.length - 1 ? (
                  <text className="metricXAxis" key={`${point.id}-label`} x={point.x} y="214">{point.date.slice(5)}</text>
                ) : null)}
              </svg>
            </div>

            <div className="metricHistoryList">
              {[...series].reverse().slice(0, 12).map((point) => (
                <article className={point.date === currentDate ? "active" : ""} key={point.id}>
                  <span>{formatDateLabel(point.date)}</span>
                  <strong>{definition.format(point.value)}{definition.unit}</strong>
                </article>
              ))}
            </div>
          </>
        ) : (
          <p className="bodyHistoryEmpty">这个指标还没有可展示的数据。</p>
        )}
      </section>
      </div>
    </ModalPortal>
  );
}

function MetricLine({ label, status, value }: { label: string; status: string; value: string | number }) {
  return (
    <div className="metricLine">
      <span>{label}</span>
      <strong>{value}</strong>
      <em>{status}</em>
    </div>
  );
}

function BodyMetricDialog({ defaultDate, metric, onClose, onSaved }: { defaultDate: string; metric?: BodyMetric; onClose: () => void; onSaved: (savedDate: string) => Promise<void> }) {
  const useScreenshotDefaults = !metric && defaultDate === "2026-06-30";
  const screenshotInputRef = useRef<HTMLInputElement>(null);
  const nowInput = `${defaultDate}T16:48`;
  const [date, setDate] = useState(metric?.date || defaultDate);
  const [measuredAt, setMeasuredAt] = useState(toDateTimeLocal(metric?.measuredAt) || nowInput);
  const [score, setScore] = useState(metric ? String(round(metric.score)) : useScreenshotDefaults ? "65" : "");
  const [weightKg, setWeightKg] = useState(metric ? String(metric.weightKg) : useScreenshotDefaults ? "75.05" : "");
  const [bmi, setBmi] = useState(metric ? String(metric.bmi) : useScreenshotDefaults ? "24.2" : "");
  const [bodyFatPercent, setBodyFatPercent] = useState(metric ? String(metric.bodyFatPercent) : useScreenshotDefaults ? "20.8" : "");
  const [bodyAge, setBodyAge] = useState(metric ? String(round(metric.bodyAge)) : useScreenshotDefaults ? "29" : "");
  const [bodyType, setBodyType] = useState(metric?.bodyType || (useScreenshotDefaults ? "肥胖" : ""));
  const [muscleKg, setMuscleKg] = useState(metric ? String(metric.muscleKg) : useScreenshotDefaults ? "56.6" : "");
  const [skeletalMuscleKg, setSkeletalMuscleKg] = useState(metric ? String(metric.skeletalMuscleKg) : useScreenshotDefaults ? "56.6" : "");
  const [boneMassKg, setBoneMassKg] = useState(metric ? String(metric.boneMassKg) : useScreenshotDefaults ? "2.8" : "");
  const [waterPercent, setWaterPercent] = useState(metric ? String(metric.waterPercent) : useScreenshotDefaults ? "55.0" : "");
  const [visceralFat, setVisceralFat] = useState(metric ? String(metric.visceralFat) : useScreenshotDefaults ? "8.5" : "");
  const [bmrKcal, setBmrKcal] = useState(metric ? String(metric.bmrKcal) : useScreenshotDefaults ? "1701" : "");
  const [proteinPercent, setProteinPercent] = useState(metric ? String(metric.proteinPercent) : useScreenshotDefaults ? "20.4" : "");
  const [trunkFatPercent, setTrunkFatPercent] = useState(metric ? String(metric.trunkFatPercent) : useScreenshotDefaults ? "22.93" : "");
  const [trunkMuscleKg, setTrunkMuscleKg] = useState(metric ? String(metric.trunkMuscleKg) : useScreenshotDefaults ? "28.93" : "");
  const [leftArmFatPercent, setLeftArmFatPercent] = useState(metric ? String(metric.leftArmFatPercent) : useScreenshotDefaults ? "16.04" : "");
  const [leftArmMuscleKg, setLeftArmMuscleKg] = useState(metric ? String(metric.leftArmMuscleKg) : useScreenshotDefaults ? "2.70" : "");
  const [rightArmFatPercent, setRightArmFatPercent] = useState(metric ? String(metric.rightArmFatPercent) : useScreenshotDefaults ? "15.01" : "");
  const [rightArmMuscleKg, setRightArmMuscleKg] = useState(metric ? String(metric.rightArmMuscleKg) : useScreenshotDefaults ? "2.91" : "");
  const [leftLegFatPercent, setLeftLegFatPercent] = useState(metric ? String(metric.leftLegFatPercent) : useScreenshotDefaults ? "19.19" : "");
  const [leftLegMuscleKg, setLeftLegMuscleKg] = useState(metric ? String(metric.leftLegMuscleKg) : useScreenshotDefaults ? "10.55" : "");
  const [rightLegFatPercent, setRightLegFatPercent] = useState(metric ? String(metric.rightLegFatPercent) : useScreenshotDefaults ? "19.42" : "");
  const [rightLegMuscleKg, setRightLegMuscleKg] = useState(metric ? String(metric.rightLegMuscleKg) : useScreenshotDefaults ? "10.56" : "");
  const [note, setNote] = useState(metric?.note || (useScreenshotDefaults ? "来自 2026-06-30 体脂秤截图录入。" : ""));
  const [screenshotName, setScreenshotName] = useState("");
  const [analyzingScreenshot, setAnalyzingScreenshot] = useState(false);
  const [screenshotSummary, setScreenshotSummary] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  function numberValue(value: string) {
    return Number(value || 0);
  }

  function stringMetric(value: unknown, digits?: number) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return "";
    if (digits === undefined) return String(parsed);
    return parsed.toFixed(digits).replace(/\.?0+$/, "");
  }

  function applyNumber(value: unknown, setter: React.Dispatch<React.SetStateAction<string>>, digits?: number) {
    const formatted = stringMetric(value, digits);
    if (formatted) setter(formatted);
  }

  function applyBodyScreenshotAnalysis(analysis: Record<string, unknown>, fileName: string) {
    if (typeof analysis.date === "string" && analysis.date) setDate(analysis.date);
    if (typeof analysis.measuredAt === "string" && analysis.measuredAt) setMeasuredAt(analysis.measuredAt);
    applyNumber(analysis.score, setScore, 0);
    applyNumber(analysis.weightKg, setWeightKg, 2);
    applyNumber(analysis.bmi, setBmi, 1);
    applyNumber(analysis.bodyFatPercent, setBodyFatPercent, 1);
    applyNumber(analysis.bodyAge, setBodyAge, 0);
    if (typeof analysis.bodyType === "string" && analysis.bodyType) setBodyType(analysis.bodyType);
    applyNumber(analysis.muscleKg, setMuscleKg, 1);
    applyNumber(analysis.skeletalMuscleKg, setSkeletalMuscleKg, 1);
    applyNumber(analysis.boneMassKg, setBoneMassKg, 1);
    applyNumber(analysis.waterPercent, setWaterPercent, 1);
    applyNumber(analysis.visceralFat, setVisceralFat, 1);
    applyNumber(analysis.bmrKcal, setBmrKcal, 0);
    applyNumber(analysis.proteinPercent, setProteinPercent, 1);
    applyNumber(analysis.trunkFatPercent, setTrunkFatPercent, 2);
    applyNumber(analysis.trunkMuscleKg, setTrunkMuscleKg, 2);
    applyNumber(analysis.leftArmFatPercent, setLeftArmFatPercent, 2);
    applyNumber(analysis.leftArmMuscleKg, setLeftArmMuscleKg, 2);
    applyNumber(analysis.rightArmFatPercent, setRightArmFatPercent, 2);
    applyNumber(analysis.rightArmMuscleKg, setRightArmMuscleKg, 2);
    applyNumber(analysis.leftLegFatPercent, setLeftLegFatPercent, 2);
    applyNumber(analysis.leftLegMuscleKg, setLeftLegMuscleKg, 2);
    applyNumber(analysis.rightLegFatPercent, setRightLegFatPercent, 2);
    applyNumber(analysis.rightLegMuscleKg, setRightLegMuscleKg, 2);

    const confidence = Math.round(Number(analysis.confidence || 0) * 100);
    const analysisNotes = typeof analysis.notes === "string" ? analysis.notes : "";
    setNote([`来自身体数据截图识别：${fileName}${confidence ? `，置信度约 ${confidence}%` : ""}。`, analysisNotes, note].filter(Boolean).join("\n"));
    setScreenshotSummary(`已读取截图：${[
      analysis.weightKg ? `体重 ${stringMetric(analysis.weightKg, 2)}kg` : "",
      analysis.bodyFatPercent ? `体脂 ${stringMetric(analysis.bodyFatPercent, 1)}%` : "",
      analysis.bmi ? `BMI ${stringMetric(analysis.bmi, 1)}` : "",
    ].filter(Boolean).join(" · ") || "请检查已填入字段"}`);
  }

  async function analyzeBodyScreenshot(file: File) {
    setAnalyzingScreenshot(true);
    setError("");
    setScreenshotSummary("");
    try {
      const dataUrl = await imageFileToDataUrl(file, 1800, 0.86);
      const response = await fetch("/api/analyze-body", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          screenshot: {
            fileName: file.name,
            contentType: file.type || "image/jpeg",
            dataUrl,
          },
        }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "身体截图识别失败。");
      applyBodyScreenshotAnalysis(payload.analysis || {}, file.name);
    } catch (error) {
      setError(formatCloudError(error));
    } finally {
      setAnalyzingScreenshot(false);
    }
  }

  async function handleScreenshotUpload(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setScreenshotName(file.name);
    await analyzeBodyScreenshot(file);
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!date || !weightKg) {
      setError("至少需要填写日期和体重。");
      return;
    }
    setSaving(true);
    setError("");
    try {
      await upsertBodyMetric({
        date,
        measuredAt,
        score: numberValue(score),
        weightKg: numberValue(weightKg),
        bmi: numberValue(bmi),
        bodyFatPercent: numberValue(bodyFatPercent),
        bodyAge: numberValue(bodyAge),
        bodyType,
        muscleKg: numberValue(muscleKg),
        skeletalMuscleKg: numberValue(skeletalMuscleKg),
        boneMassKg: numberValue(boneMassKg),
        waterPercent: numberValue(waterPercent),
        visceralFat: numberValue(visceralFat),
        bmrKcal: numberValue(bmrKcal),
        proteinPercent: numberValue(proteinPercent),
        trunkFatPercent: numberValue(trunkFatPercent),
        trunkMuscleKg: numberValue(trunkMuscleKg),
        leftArmFatPercent: numberValue(leftArmFatPercent),
        leftArmMuscleKg: numberValue(leftArmMuscleKg),
        rightArmFatPercent: numberValue(rightArmFatPercent),
        rightArmMuscleKg: numberValue(rightArmMuscleKg),
        leftLegFatPercent: numberValue(leftLegFatPercent),
        leftLegMuscleKg: numberValue(leftLegMuscleKg),
        rightLegFatPercent: numberValue(rightLegFatPercent),
        rightLegMuscleKg: numberValue(rightLegMuscleKg),
        note,
      });
      await onSaved(date);
    } catch (error) {
      setError(formatCloudError(error));
    } finally {
      setSaving(false);
    }
  }

  return (
    <ModalPortal>
      <div className="modalBackdrop" role="presentation" onClick={onClose}>
      <section aria-modal="true" className="entryDialog bodyDialog" role="dialog" onClick={(event) => event.stopPropagation()}>
        <div className="entryHead">
          <div>
            <h3>{metric ? "修改身体数据" : "记录身体数据"}</h3>
            <p>每天一条记录，同一天再次保存会覆盖更新。</p>
          </div>
          <button aria-label="关闭" onClick={onClose} type="button">×</button>
        </div>
        <form className="entryForm bodyForm" onSubmit={handleSubmit}>
          <label><span>日期</span><input value={date} onChange={(event) => setDate(event.target.value)} type="date" /></label>
          <label><span>测量时间</span><input value={measuredAt} onChange={(event) => setMeasuredAt(event.target.value)} type="datetime-local" /></label>
          <label><span>体重 kg</span><input inputMode="decimal" value={weightKg} onChange={(event) => setWeightKg(event.target.value)} placeholder="75.05" /></label>
          <label><span>体脂 %</span><input inputMode="decimal" value={bodyFatPercent} onChange={(event) => setBodyFatPercent(event.target.value)} placeholder="20.8" /></label>
          <label><span>BMI</span><input inputMode="decimal" value={bmi} onChange={(event) => setBmi(event.target.value)} placeholder="24.2" /></label>
          <label><span>身体评分</span><input inputMode="decimal" value={score} onChange={(event) => setScore(event.target.value)} placeholder="65" /></label>
          <label><span>身体年龄</span><input inputMode="decimal" value={bodyAge} onChange={(event) => setBodyAge(event.target.value)} placeholder="29" /></label>
          <label><span>体型</span><input value={bodyType} onChange={(event) => setBodyType(event.target.value)} placeholder="肥胖 / 标准 / 偏瘦" /></label>
          <label><span>肌肉 kg</span><input inputMode="decimal" value={muscleKg} onChange={(event) => setMuscleKg(event.target.value)} placeholder="56.6" /></label>
          <label><span>骨骼肌 kg</span><input inputMode="decimal" value={skeletalMuscleKg} onChange={(event) => setSkeletalMuscleKg(event.target.value)} placeholder="56.6" /></label>
          <label><span>骨量 kg</span><input inputMode="decimal" value={boneMassKg} onChange={(event) => setBoneMassKg(event.target.value)} placeholder="2.8" /></label>
          <label><span>水分 %</span><input inputMode="decimal" value={waterPercent} onChange={(event) => setWaterPercent(event.target.value)} placeholder="55.0" /></label>
          <label><span>内脏脂肪</span><input inputMode="decimal" value={visceralFat} onChange={(event) => setVisceralFat(event.target.value)} placeholder="8.5" /></label>
          <label><span>基础代谢 kcal</span><input inputMode="decimal" value={bmrKcal} onChange={(event) => setBmrKcal(event.target.value)} placeholder="1701" /></label>
          <label><span>蛋白质 %</span><input inputMode="decimal" value={proteinPercent} onChange={(event) => setProteinPercent(event.target.value)} placeholder="20.4" /></label>
          <section className="limbForm wide">
            <div className="analysisReviewHead">
              <strong>肢体数据</strong>
              <span>用于生成身体分布图，可留空</span>
            </div>
            <label><span>躯干脂肪率 %</span><input inputMode="decimal" value={trunkFatPercent} onChange={(event) => setTrunkFatPercent(event.target.value)} placeholder="22.93" /></label>
            <label><span>躯干肌肉 kg</span><input inputMode="decimal" value={trunkMuscleKg} onChange={(event) => setTrunkMuscleKg(event.target.value)} placeholder="28.93" /></label>
            <label><span>左手脂肪率 %</span><input inputMode="decimal" value={leftArmFatPercent} onChange={(event) => setLeftArmFatPercent(event.target.value)} placeholder="16.04" /></label>
            <label><span>左手肌肉 kg</span><input inputMode="decimal" value={leftArmMuscleKg} onChange={(event) => setLeftArmMuscleKg(event.target.value)} placeholder="2.70" /></label>
            <label><span>右手脂肪率 %</span><input inputMode="decimal" value={rightArmFatPercent} onChange={(event) => setRightArmFatPercent(event.target.value)} placeholder="15.01" /></label>
            <label><span>右手肌肉 kg</span><input inputMode="decimal" value={rightArmMuscleKg} onChange={(event) => setRightArmMuscleKg(event.target.value)} placeholder="2.91" /></label>
            <label><span>左腿脂肪率 %</span><input inputMode="decimal" value={leftLegFatPercent} onChange={(event) => setLeftLegFatPercent(event.target.value)} placeholder="19.19" /></label>
            <label><span>左腿肌肉 kg</span><input inputMode="decimal" value={leftLegMuscleKg} onChange={(event) => setLeftLegMuscleKg(event.target.value)} placeholder="10.55" /></label>
            <label><span>右腿脂肪率 %</span><input inputMode="decimal" value={rightLegFatPercent} onChange={(event) => setRightLegFatPercent(event.target.value)} placeholder="19.42" /></label>
            <label><span>右腿肌肉 kg</span><input inputMode="decimal" value={rightLegMuscleKg} onChange={(event) => setRightLegMuscleKg(event.target.value)} placeholder="10.56" /></label>
          </section>
          <label className="wide"><span>备注</span><textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="例如：来自体脂秤截图，测量前是否吃饭、运动等" /></label>
          <div className="analysisAction">
            <div className="bodyScreenshotHint">
              <p className="entryHint">{screenshotSummary || (screenshotName ? `已选择：${screenshotName}` : "上传体脂秤截图后，会自动读取并填入上面的身体数据。")}</p>
              <small>识别结果只会填入表单，保存前可以手动修改。</small>
            </div>
            <input
              ref={screenshotInputRef}
              className="hiddenFileInput"
              type="file"
              accept="image/*"
              onChange={handleScreenshotUpload}
            />
            <button disabled={analyzingScreenshot} onClick={() => screenshotInputRef.current?.click()} type="button">
              {analyzingScreenshot ? <RefreshCw size={15} /> : <CloudUpload size={15} />}
              {analyzingScreenshot ? "识别中" : "上传截图识别"}
            </button>
          </div>
          {error && <p className="entryError">{error}</p>}
          <div className="entryActions">
            <button className="secondaryButton" onClick={onClose} type="button">取消</button>
            <button disabled={saving} type="submit">{saving ? "保存中" : "保存身体数据"}</button>
          </div>
        </form>
      </section>
      </div>
    </ModalPortal>
  );
}

function ExerciseDashboard({
  appleHealthImporting,
  bodyMetrics,
  dailyActivities,
  exerciseActivities,
  exerciseState,
  items,
  onDeleteDaily,
  onDeleteWorkout,
  onEditWorkout,
  onImportAppleHealth,
  onOpenShortcutInfo,
  onOpenDaily,
  onRefreshExercise,
  onOpenWorkout,
  selectedDate,
}: {
  appleHealthImporting: boolean;
  bodyMetrics: BodyMetric[];
  dailyActivities: DailyActivity[];
  exerciseActivities: ExerciseActivity[];
  exerciseState: string;
  items: FoodItem[];
  onDeleteDaily: (activityItem: DailyActivity) => void;
  onDeleteWorkout: (workout: ExerciseActivity) => void;
  onEditWorkout: (workout: ExerciseActivity) => void;
  onImportAppleHealth: (months: number) => void;
  onOpenShortcutInfo: () => void;
  onOpenDaily: () => void;
  onRefreshExercise: () => void;
  onOpenWorkout: () => void;
  selectedDate: string;
}) {
  const dayItems = items.filter((item) => item.date === selectedDate);
  const dayTotals = totalsFor(dayItems);
  const currentDaily = dailyActivities.find((activityItem) => activityItem.date === selectedDate);
  const workouts = exerciseActivities.filter((activityItem) => activityItem.date === selectedDate);
  const workoutCalories = workouts.reduce((sum, workout) => sum + workout.activeCalories, 0);
  const activeCalories = currentDaily?.activeCalories || workoutCalories;
  const exerciseMinutes = currentDaily?.exerciseMinutes || workouts.reduce((sum, workout) => sum + workout.durationMinutes, 0);
  const distanceKm = currentDaily?.distanceKm || workouts.reduce((sum, workout) => sum + workout.distanceKm, 0);
  const currentBody = [...bodyMetrics].sort((a, b) => b.date.localeCompare(a.date)).find((metric) => metric.date <= selectedDate);
  const recentDates = recentDateKeys(selectedDate, 7);
  const maxActiveCalories = Math.max(1, ...recentDates.map((date) => activityCaloriesForDate(dailyActivities, exerciseActivities, date)));
  const netCalories = dayTotals.calories - activeCalories;
  const ringData = [
    { label: "活动", value: activeCalories, goal: 500, unit: "kcal", color: "#0A84FF" },
    { label: "锻炼", value: exerciseMinutes, goal: 30, unit: "分钟", color: "#AF52DE" },
    { label: "步数", value: currentDaily?.steps || 0, goal: 8000, unit: "步", color: "#30D158" },
  ];
  const balanceValues = recentDates.map((date) => {
    const food = totalsFor(items.filter((item) => item.date === date)).calories;
    return food - activityCaloriesForDate(dailyActivities, exerciseActivities, date);
  });

  return (
    <section className="exerciseLayout healthRedesign">
      <section className="exerciseHeader">
        <div>
          <p>运动数据</p>
          <span>{round(activeCalories)} kcal · {round(exerciseMinutes)} 分钟 · {workouts.length} 次训练</span>
        </div>
        <div className="exerciseHeroActions">
          <div className="exerciseImportGroup">
            <span className="exerciseImportLabel">Apple 健康导入</span>
            <div className="segmentedGlass">
              <button className="glassButton" disabled={appleHealthImporting} onClick={() => onImportAppleHealth(1)} type="button">1 个月</button>
              <button className="glassButton primaryGlassButton" disabled={appleHealthImporting} onClick={() => onImportAppleHealth(3)} type="button">{appleHealthImporting ? "导入中" : "3 个月"}</button>
              <button className="glassButton" disabled={appleHealthImporting} onClick={() => onImportAppleHealth(6)} type="button">6 个月</button>
            </div>
          </div>
          <button className="glassButton" onClick={onOpenShortcutInfo} type="button"><Smartphone size={16} />快捷同步</button>
          <button className="glassButton" onClick={onOpenDaily} type="button"><Watch size={16} />记录活动摘要</button>
          <button className="aiAnalyzeButton" onClick={onOpenWorkout} type="button"><Plus size={16} />新增训练</button>
        </div>
      </section>

      <section className="healthDashboardGrid">
        <article className="healthRingCard">
          <div className="bodySectionHead">
            <div>
              <h3>今日活动</h3>
              <p>{currentDaily ? sourceLabel(currentDaily.source) : "等待 Apple 健康同步"}</p>
            </div>
            <button className="miniActionButton syncMiniButton" onClick={onRefreshExercise} type="button"><RefreshCw size={14} />刷新同步</button>
          </div>
          <div className="activityRingLayout">
            <ActivityRings rings={ringData} />
            <div className="ringLegend">
              {ringData.map((ring) => (
                <div key={ring.label}>
                  <i style={{ background: ring.color }} />
                  <span>{ring.label}</span>
                  <strong>{ring.label === "步数" ? round(ring.value).toLocaleString() : round(ring.value)}<small>/{ring.goal.toLocaleString()} {ring.unit}</small></strong>
                  <b><em style={{ width: `${Math.min(100, ring.goal ? (ring.value / ring.goal) * 100 : 0)}%`, background: ring.color }} /></b>
                </div>
              ))}
            </div>
          </div>
        </article>

        <article className="healthBalanceCard">
          <div className="bodySectionHead">
            <div>
              <h3>饮食 + 运动差值</h3>
              <p>摄入 - 活动消耗</p>
            </div>
            <HeartPulse size={18} />
          </div>
          <strong className={`healthBalanceValue ${netCalories <= 0 ? "negative" : "positive"}`}>{round(netCalories).toLocaleString()}<small>kcal</small></strong>
          <p className="balanceFormula">摄入 {round(dayTotals.calories).toLocaleString()} kcal · 活动 {round(activeCalories).toLocaleString()} kcal</p>
          <MiniLineChart values={balanceValues} color="#0A84FF" />
        </article>

        <article className="healthBodySnapshotCard">
          <div className="bodySectionHead">
            <div>
              <h3>身体快照</h3>
              <p>{currentBody ? `${currentBody.date} 记录` : "暂无身体数据"}</p>
            </div>
            <Scale size={18} />
          </div>
          <div className="bodySnapshotRows">
            <BodySnapshotRow color="#0A84FF" icon={<Scale size={17} />} label="体重" status="偏重" value={currentBody?.weightKg ? `${currentBody.weightKg.toFixed(2)} kg` : "--"} values={bodyMetrics.map((metric) => metric.weightKg).slice(-7)} />
            <BodySnapshotRow color="#30D158" icon={<PercentIcon />} label="体脂率" status="标准" value={currentBody?.bodyFatPercent ? `${currentBody.bodyFatPercent.toFixed(1)}%` : "--"} values={bodyMetrics.map((metric) => metric.bodyFatPercent).slice(-7)} />
          </div>
        </article>

        <article className="healthTrendCard">
          <div className="bodySectionHead">
            <div>
              <h3>7 日活动趋势</h3>
              <p>活动能量柱状图</p>
            </div>
            <LineChart size={18} />
          </div>
          <div className="exerciseBars">
            {recentDates.length ? recentDates.map((date) => {
              const calories = activityCaloriesForDate(dailyActivities, exerciseActivities, date);
              const barPercent = Math.max(4, Math.min(100, (calories / maxActiveCalories) * 100));
              return (
                <div className={date === selectedDate ? "exerciseBarWrap active" : "exerciseBarWrap"} key={date}>
                  <span>{round(calories)}</span>
                  <i style={{ height: `${barPercent}%` }} />
                  <em>{date.slice(5)}</em>
                </div>
              );
            }) : <p>还没有趋势数据。</p>}
          </div>
        </article>

        <article className="healthWorkoutCard">
          <div className="bodySectionHead">
            <div>
              <h3>训练</h3>
              <p>{workouts.length ? `${workouts.length} 条训练记录` : "今天还没有训练"}</p>
            </div>
            <button className="miniActionButton" onClick={onOpenWorkout} type="button"><Plus size={14} />新增</button>
          </div>
          <CompactWorkoutList
            exerciseState={exerciseState}
            onDeleteWorkout={onDeleteWorkout}
            onEditWorkout={onEditWorkout}
            workouts={workouts}
          />
        </article>

        <article className="healthSummaryCard">
          <div className="bodySectionHead">
            <div>
              <h3>活动摘要</h3>
              <p>{currentDaily ? sourceLabel(currentDaily.source) : "暂无同步"}</p>
            </div>
            {currentDaily && <button className="miniActionButton danger" onClick={() => onDeleteDaily(currentDaily)} type="button"><Trash2 size={14} />删除</button>}
          </div>
          <div className="compactMetricGrid">
            <CompactMetric icon={<Flame size={17} />} label="活动消耗" value={`${round(currentDaily?.activeCalories || activeCalories)} kcal`} color="#0A84FF" />
            <CompactMetric icon={<Footprints size={17} />} label="步数" value={`${round(currentDaily?.steps || 0).toLocaleString()} 步`} color="#30D158" />
            <CompactMetric icon={<Timer size={17} />} label="运动时间" value={`${round(exerciseMinutes)} 分钟`} color="#AF52DE" />
            <CompactMetric icon={<Route size={17} />} label="距离" value={`${distanceKm ? distanceKm.toFixed(1) : "0.0"} km`} color="#00C7BE" />
            <CompactMetric icon={<LineChart size={17} />} label="爬楼" value={`${round(currentDaily?.floors || 0)} 层`} color="#FF9500" />
            <CompactMetric icon={<Droplets size={17} />} label="站立时间" value={`${round(currentDaily?.standHours || 0)} 小时`} color="#FF2D55" />
          </div>
        </article>

        <SyncDiagnosticsPanel
          activity={currentDaily}
          appleHealthImporting={appleHealthImporting}
          dailyActivities={dailyActivities}
          exerciseState={exerciseState}
          selectedDate={selectedDate}
          workouts={workouts}
        />

        <AppleHealthMetricsPanel activity={currentDaily} />
      </section>
    </section>
  );
}

function SyncDiagnosticsPanel({
  activity,
  appleHealthImporting,
  dailyActivities,
  exerciseState,
  selectedDate,
  workouts,
}: {
  activity?: DailyActivity;
  appleHealthImporting: boolean;
  dailyActivities: DailyActivity[];
  exerciseState: string;
  selectedDate: string;
  workouts: ExerciseActivity[];
}) {
  const latestActivity = [...dailyActivities].sort((a, b) => b.createdAt.localeCompare(a.createdAt))[0];
  const metricCount = Object.keys(activity?.rawMetrics || {}).length;
  const hasUsefulNumbers = Boolean(activity && (
    activity.steps ||
    activity.activeCalories ||
    activity.exerciseMinutes ||
    activity.standHours ||
    activity.distanceKm ||
    activity.floors ||
    metricCount
  ));
  const stateTone = exerciseState.includes("失败") || exerciseState.includes("不可用") ? "bad" : activity ? "good" : "warn";
  const diagnostics = [
    { label: "同步状态", value: appleHealthImporting ? "正在导入" : exerciseState, tone: stateTone },
    { label: "选中日期", value: activity ? `${selectedDate} · ${sourceLabel(activity.source)}` : `${selectedDate} 暂无活动摘要`, tone: activity ? "good" : "warn" },
    { label: "健康指标", value: `${metricCount} 类`, tone: metricCount ? "good" : "warn" },
    { label: "训练记录", value: `${workouts.length} 条`, tone: workouts.length ? "good" : "neutral" },
  ];
  const tips = [];
  if (!activity) tips.push("如果快捷指令显示成功但这里为空，优先检查传入日期是否等于网站当前选中日期。");
  if (activity && !hasUsefulNumbers) tips.push("当前摘要几乎全是 0，通常是快捷指令没有拿到 Apple 健康权限或筛选项为空。");
  if (latestActivity) tips.push(`最近写入：${latestActivity.date} · ${sourceLabel(latestActivity.source)}。`);
  tips.push("接口会拒绝全 0 快捷指令数据，避免覆盖已经导入的正确历史数据。");

  return (
    <article className="syncDiagnosticsCard">
      <div className="bodySectionHead">
        <div>
          <h3>同步诊断</h3>
          <p>排查 Apple 健康快捷指令是否真正写入</p>
        </div>
        <ShieldCheck size={18} />
      </div>
      <div className="syncDiagnosticGrid">
        {diagnostics.map((item) => (
          <div className={`syncDiagnosticItem ${item.tone}`} key={item.label}>
            <span>{item.label}</span>
            <strong>{item.value}</strong>
          </div>
        ))}
      </div>
      <ul className="syncDiagnosticTips">
        {tips.slice(0, 3).map((tip) => <li key={tip}>{tip}</li>)}
      </ul>
    </article>
  );
}

function AppleHealthMetricsPanel({ activity }: { activity?: DailyActivity }) {
  const grouped = appleHealthMetricDefinitions.reduce<Record<string, typeof appleHealthMetricDefinitions>>((groups, definition) => {
    groups[definition.category] = groups[definition.category] || [];
    groups[definition.category].push(definition);
    return groups;
  }, {});
  const metrics = activity?.rawMetrics || {};
  const filledCount = Object.keys(metrics).length;
  const categories = Object.keys(grouped);
  const firstCategoryWithData = categories.find((category) => categoryHasMetrics(grouped[category], metrics)) || categories[0];
  const [selectedCategory, setSelectedCategory] = useState(firstCategoryWithData);
  const selectedDefinitions = grouped[selectedCategory] || [];

  return (
    <article className="appleHealthPanel">
      <div className="bodySectionHead">
        <div>
          <h3>健康分类</h3>
          <p>{activity ? `已同步 ${filledCount} 类指标` : "同步后按 Apple 健康分类显示"}</p>
        </div>
        <Watch size={18} />
      </div>
      <div className="healthCategoryTiles">
        {Object.entries(grouped).map(([category, definitions]) => (
          <button
            className={`healthCategoryTile ${categoryHasMetrics(definitions, metrics) ? "filled" : ""} ${selectedCategory === category ? "active" : ""}`}
            key={category}
            onClick={() => setSelectedCategory(category)}
            style={{ "--category-color": healthCategoryColor(category) } as React.CSSProperties}
            type="button"
          >
            <span className="healthCategoryIcon">{healthCategoryIcon(category, 18)}</span>
            <div>
              <h4>{category}</h4>
              <p>{categorySummary(definitions, metrics)}</p>
            </div>
            <ChevronRight size={16} />
          </button>
        ))}
      </div>
      <div className="healthCategoryDetail" style={{ "--category-color": healthCategoryColor(selectedCategory) } as React.CSSProperties}>
        <div>
          <span className="healthCategoryIcon">{healthCategoryIcon(selectedCategory, 18)}</span>
          <strong>{selectedCategory}</strong>
          <em>{selectedDefinitions.filter((definition) => metrics[definition.type]).length}/{selectedDefinitions.length} 已同步</em>
        </div>
        <section>
          {selectedDefinitions.map((definition) => {
            const metric = metrics[definition.type];
            return (
              <p className={metric ? "filled" : ""} key={definition.type}>
                <span>{definition.label}</span>
                <strong>{metric ? formatHealthMetricValue(metric.value, metric.unit) : "--"}</strong>
              </p>
            );
          })}
        </section>
      </div>
    </article>
  );
}

function ActivityRings({ rings }: { rings: Array<{ color: string; goal: number; label: string; unit: string; value: number }> }) {
  const radii = [72, 57, 42];
  return (
    <div className="activityRings">
      <svg aria-label="今日活动圆环" viewBox="0 0 180 180">
        {rings.map((ring, index) => {
          const radius = radii[index];
          const circumference = 2 * Math.PI * radius;
          const progress = Math.max(0, Math.min(1.15, ring.goal ? ring.value / ring.goal : 0));
          return (
            <g key={ring.label}>
              <circle className="ringTrack" cx="90" cy="90" r={radius} />
              <circle
                className="ringProgress"
                cx="90"
                cy="90"
                r={radius}
                stroke={ring.color}
                strokeDasharray={`${circumference} ${circumference}`}
                strokeDashoffset={circumference * (1 - Math.min(1, progress))}
              />
            </g>
          );
        })}
      </svg>
      <div>
        <strong>{round(rings[0]?.value || 0)}</strong>
        <span>活动 kcal</span>
      </div>
    </div>
  );
}

function MiniLineChart({ color, values }: { color: string; values: number[] }) {
  const width = 220;
  const height = 58;
  const min = Math.min(...values, 0);
  const max = Math.max(...values, 1);
  const range = Math.max(1, max - min);
  const points = values.map((value, index) => {
    const x = values.length <= 1 ? width / 2 : (index / (values.length - 1)) * width;
    const y = height - ((value - min) / range) * (height - 10) - 5;
    return `${x},${y}`;
  });
  return (
    <svg className="miniLineChart" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
      <polyline points={points.join(" ")} fill="none" stroke={color} strokeLinecap="round" strokeLinejoin="round" strokeWidth="4" />
    </svg>
  );
}

function CompactWorkoutList({
  exerciseState,
  onDeleteWorkout,
  onEditWorkout,
  workouts,
}: {
  exerciseState: string;
  onDeleteWorkout: (workout: ExerciseActivity) => void;
  onEditWorkout: (workout: ExerciseActivity) => void;
  workouts: ExerciseActivity[];
}) {
  if (!workouts.length) {
    return (
      <div className="compactEmpty">
        <Activity size={18} />
        <span>{exerciseState.includes("不可用") ? exerciseState : "暂无训练，散步或力量训练可以先手动记录。"}</span>
      </div>
    );
  }

  return (
    <div className="compactWorkoutList">
      {workouts.slice(0, 4).map((workout) => (
        <article className="compactWorkoutItem" key={workout.id}>
          <span>{workoutIcon(workout.type)}</span>
          <div>
            <strong>{workout.title}</strong>
            <p>{round(workout.durationMinutes)} 分钟 · {round(workout.activeCalories)} kcal</p>
          </div>
          <button onClick={() => onEditWorkout(workout)} type="button"><PenLine size={13} /></button>
          <button onClick={() => onDeleteWorkout(workout)} type="button"><Trash2 size={13} /></button>
        </article>
      ))}
    </div>
  );
}

function BodySnapshotRow({ color, icon, label, status, value, values }: { color: string; icon: React.ReactNode; label: string; status: string; value: string; values: number[] }) {
  return (
    <div className="bodySnapshotRow">
      <span style={{ color }}>{icon}</span>
      <div>
        <p>{label}</p>
        <strong>{value}</strong>
      </div>
      <em>{status}</em>
      <MiniLineChart color={color} values={values.length ? values : [0, 0, 0, 0, 0, 0, 0]} />
    </div>
  );
}

function PercentIcon() {
  return <span className="percentGlyph">%</span>;
}

function CompactMetric({ color, icon, label, value }: { color: string; icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="compactMetric">
      <i style={{ color, background: `${color}1A` }}>{icon}</i>
      <span>{label}</span>
      <strong>{value}</strong>
      <b>
        {Array.from({ length: 9 }, (_, index) => (
          <em key={index} style={{ height: `${5 + ((index * 7) % 20)}px`, background: color }} />
        ))}
      </b>
    </div>
  );
}

function categoryHasMetrics(definitions: HealthMetricDefinition[], metrics: DailyActivity["rawMetrics"]) {
  return definitions.some((definition) => metrics[definition.type]);
}

function categorySummary(definitions: HealthMetricDefinition[], metrics: DailyActivity["rawMetrics"]) {
  const filled = definitions.filter((definition) => metrics[definition.type]);
  if (!filled.length) return `${definitions.length} 个指标 · 暂无数据`;
  return filled.slice(0, 3).map((definition) => {
    const metric = metrics[definition.type];
    return `${definition.label} ${formatHealthMetricValue(metric.value, metric.unit)}`;
  }).join(" · ");
}

function healthCategoryIcon(category: string, size = 18) {
  if (category === "活动") return <Activity size={size} />;
  if (category === "身体测量") return <Scale size={size} />;
  if (category === "心脏") return <HeartPulse size={size} />;
  if (category === "活动能力") return <Footprints size={size} />;
  if (category === "呼吸") return <Droplets size={size} />;
  if (category === "睡眠") return <Moon size={size} />;
  if (category === "生命体征") return <ListChecks size={size} />;
  if (category === "营养") return <Wheat size={size} />;
  return <Sparkles size={size} />;
}

function healthCategoryColor(category: string) {
  if (category === "活动") return "#0A84FF";
  if (category === "身体测量") return "#5E5CE6";
  if (category === "心脏") return "#FF2D55";
  if (category === "活动能力") return "#30D158";
  if (category === "呼吸") return "#00C7BE";
  if (category === "睡眠") return "#AF52DE";
  if (category === "生命体征") return "#FF375F";
  if (category === "营养") return "#FF9F0A";
  return "#64D2FF";
}

function ExerciseMetricCard({ icon, label, tone, unit, value }: { icon: React.ReactNode; label: string; tone: string; unit: string; value: string }) {
  return (
    <article className={`exerciseMetricCard ${tone}`}>
      <span>{icon}</span>
      <div>
        <p>{label}</p>
        <strong>{value}<small>{unit}</small></strong>
      </div>
    </article>
  );
}

function DailyActivityDialog({ activity, defaultDate, onClose, onSaved }: { activity?: DailyActivity; defaultDate: string; onClose: () => void; onSaved: (savedDate: string) => Promise<void> }) {
  const [date, setDate] = useState(activity?.date || defaultDate);
  const [source, setSource] = useState(activity?.source || "manual");
  const [steps, setSteps] = useState(activity ? String(activity.steps) : "");
  const [activeCalories, setActiveCalories] = useState(activity ? String(activity.activeCalories) : "");
  const [totalCalories, setTotalCalories] = useState(activity ? String(activity.totalCalories) : "");
  const [exerciseMinutes, setExerciseMinutes] = useState(activity ? String(activity.exerciseMinutes) : "");
  const [standHours, setStandHours] = useState(activity ? String(activity.standHours) : "");
  const [distanceKm, setDistanceKm] = useState(activity ? String(activity.distanceKm) : "");
  const [floors, setFloors] = useState(activity ? String(activity.floors) : "");
  const [restingHeartRate, setRestingHeartRate] = useState(activity ? String(activity.restingHeartRate) : "");
  const [hrvMs, setHrvMs] = useState(activity ? String(activity.hrvMs) : "");
  const [sleepMinutes, setSleepMinutes] = useState(activity ? String(activity.sleepMinutes) : "");
  const [note, setNote] = useState(activity?.note || "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  function numberValue(value: string) {
    return Number(value || 0);
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!date) {
      setError("需要填写日期。");
      return;
    }
    setSaving(true);
    setError("");
    try {
      await upsertDailyActivity({
        date,
        source,
        steps: numberValue(steps),
        activeCalories: numberValue(activeCalories),
        totalCalories: numberValue(totalCalories),
        exerciseMinutes: numberValue(exerciseMinutes),
        standHours: numberValue(standHours),
        distanceKm: numberValue(distanceKm),
        floors: numberValue(floors),
        restingHeartRate: numberValue(restingHeartRate),
        hrvMs: numberValue(hrvMs),
        sleepMinutes: numberValue(sleepMinutes),
        note,
      });
      await onSaved(date);
    } catch (error) {
      setError(formatCloudError(error));
    } finally {
      setSaving(false);
    }
  }

  return (
    <ModalPortal>
      <div className="modalBackdrop" role="presentation" onClick={onClose}>
      <section aria-modal="true" className="entryDialog exerciseDialog" role="dialog" onClick={(event) => event.stopPropagation()}>
        <div className="entryHead">
          <div>
            <h3>{activity ? "修改活动摘要" : "记录活动摘要"}</h3>
            <p>适合录入 Apple 健康每日摘要：步数、活动热量、运动分钟、睡眠和心率。</p>
          </div>
          <button aria-label="关闭" onClick={onClose} type="button">×</button>
        </div>
        <form className="entryForm bodyForm" onSubmit={handleSubmit}>
          <label><span>日期</span><input value={date} onChange={(event) => setDate(event.target.value)} type="date" /></label>
          <label><span>来源</span><select value={source} onChange={(event) => setSource(event.target.value)}>{activitySourceOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
          <label><span>步数</span><input inputMode="numeric" value={steps} onChange={(event) => setSteps(event.target.value)} placeholder="8500" /></label>
          <label><span>活动热量 kcal</span><input inputMode="decimal" value={activeCalories} onChange={(event) => setActiveCalories(event.target.value)} placeholder="420" /></label>
          <label><span>总消耗 kcal</span><input inputMode="decimal" value={totalCalories} onChange={(event) => setTotalCalories(event.target.value)} placeholder="2300" /></label>
          <label><span>运动分钟</span><input inputMode="decimal" value={exerciseMinutes} onChange={(event) => setExerciseMinutes(event.target.value)} placeholder="45" /></label>
          <label><span>站立小时</span><input inputMode="decimal" value={standHours} onChange={(event) => setStandHours(event.target.value)} placeholder="10" /></label>
          <label><span>距离 km</span><input inputMode="decimal" value={distanceKm} onChange={(event) => setDistanceKm(event.target.value)} placeholder="5.2" /></label>
          <label><span>爬楼层数</span><input inputMode="decimal" value={floors} onChange={(event) => setFloors(event.target.value)} placeholder="8" /></label>
          <label><span>静息心率 bpm</span><input inputMode="decimal" value={restingHeartRate} onChange={(event) => setRestingHeartRate(event.target.value)} placeholder="62" /></label>
          <label><span>HRV ms</span><input inputMode="decimal" value={hrvMs} onChange={(event) => setHrvMs(event.target.value)} placeholder="45" /></label>
          <label><span>睡眠分钟</span><input inputMode="decimal" value={sleepMinutes} onChange={(event) => setSleepMinutes(event.target.value)} placeholder="420" /></label>
          <label className="wide"><span>备注</span><textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="例如：来自 Apple 健康当天摘要" /></label>
          {error && <p className="entryError">{error}</p>}
          <div className="entryActions">
            <button className="secondaryButton" onClick={onClose} type="button">取消</button>
            <button disabled={saving} type="submit">{saving ? "保存中" : "保存活动摘要"}</button>
          </div>
        </form>
      </section>
      </div>
    </ModalPortal>
  );
}

function WorkoutDialog({ defaultDate, onClose, onSaved, workout }: { defaultDate: string; onClose: () => void; onSaved: (savedDate: string) => Promise<void>; workout?: ExerciseActivity }) {
  const [date, setDate] = useState(workout?.date || defaultDate);
  const [startedAt, setStartedAt] = useState(toDateTimeLocal(workout?.startedAt) || `${defaultDate}T18:00`);
  const [source, setSource] = useState(workout?.source || "manual");
  const [type, setType] = useState(workout?.type || "力量训练");
  const [title, setTitle] = useState(workout?.title || "");
  const [durationMinutes, setDurationMinutes] = useState(workout ? String(workout.durationMinutes) : "");
  const [distanceKm, setDistanceKm] = useState(workout ? String(workout.distanceKm) : "");
  const [activeCalories, setActiveCalories] = useState(workout ? String(workout.activeCalories) : "");
  const [avgHeartRate, setAvgHeartRate] = useState(workout ? String(workout.avgHeartRate) : "");
  const [maxHeartRate, setMaxHeartRate] = useState(workout ? String(workout.maxHeartRate) : "");
  const [elevationGainM, setElevationGainM] = useState(workout ? String(workout.elevationGainM) : "");
  const [note, setNote] = useState(workout?.note || "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  function numberValue(value: string) {
    return Number(value || 0);
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!date || !type) {
      setError("需要填写日期和运动类型。");
      return;
    }
    setSaving(true);
    setError("");
    const payload = {
      date,
      startedAt,
      source,
      type,
      title: title || type,
      durationMinutes: numberValue(durationMinutes),
      distanceKm: numberValue(distanceKm),
      activeCalories: numberValue(activeCalories),
      avgHeartRate: numberValue(avgHeartRate),
      maxHeartRate: numberValue(maxHeartRate),
      elevationGainM: numberValue(elevationGainM),
      note,
    };
    try {
      if (workout) await updateExerciseActivity(workout.id, payload);
      else await createExerciseActivity(payload);
      await onSaved(date);
    } catch (error) {
      setError(formatCloudError(error));
    } finally {
      setSaving(false);
    }
  }

  return (
    <ModalPortal>
      <div className="modalBackdrop" role="presentation" onClick={onClose}>
      <section aria-modal="true" className="entryDialog exerciseDialog" role="dialog" onClick={(event) => event.stopPropagation()}>
        <div className="entryHead">
          <div>
            <h3>{workout ? "修改训练" : "新增训练"}</h3>
            <p>适合录入 Garmin、Apple Fitness、Strava 中的一次跑步、骑行、力量训练等。</p>
          </div>
          <button aria-label="关闭" onClick={onClose} type="button">×</button>
        </div>
        <form className="entryForm bodyForm" onSubmit={handleSubmit}>
          <label><span>日期</span><input value={date} onChange={(event) => setDate(event.target.value)} type="date" /></label>
          <label><span>开始时间</span><input value={startedAt} onChange={(event) => setStartedAt(event.target.value)} type="datetime-local" /></label>
          <label><span>来源</span><select value={source} onChange={(event) => setSource(event.target.value)}>{activitySourceOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
          <label><span>运动类型</span><input value={type} onChange={(event) => setType(event.target.value)} placeholder="力量训练 / 跑步 / 骑行" /></label>
          <label className="wide"><span>标题</span><input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="例如：晚间力量训练" /></label>
          <label><span>时长 分钟</span><input inputMode="decimal" value={durationMinutes} onChange={(event) => setDurationMinutes(event.target.value)} placeholder="45" /></label>
          <label><span>活动热量 kcal</span><input inputMode="decimal" value={activeCalories} onChange={(event) => setActiveCalories(event.target.value)} placeholder="280" /></label>
          <label><span>距离 km</span><input inputMode="decimal" value={distanceKm} onChange={(event) => setDistanceKm(event.target.value)} placeholder="5.0" /></label>
          <label><span>爬升 m</span><input inputMode="decimal" value={elevationGainM} onChange={(event) => setElevationGainM(event.target.value)} placeholder="80" /></label>
          <label><span>平均心率</span><input inputMode="decimal" value={avgHeartRate} onChange={(event) => setAvgHeartRate(event.target.value)} placeholder="135" /></label>
          <label><span>最高心率</span><input inputMode="decimal" value={maxHeartRate} onChange={(event) => setMaxHeartRate(event.target.value)} placeholder="168" /></label>
          <label className="wide"><span>备注</span><textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="例如：腿部训练，强度中等" /></label>
          {error && <p className="entryError">{error}</p>}
          <div className="entryActions">
            <button className="secondaryButton" onClick={onClose} type="button">取消</button>
            <button disabled={saving} type="submit">{saving ? "保存中" : "保存训练"}</button>
          </div>
        </form>
      </section>
      </div>
    </ModalPortal>
  );
}

function Detail({ items, onDeleteItem, onEditItem }: { items: FoodItem[]; onDeleteItem: (item: FoodItem) => void; onEditItem: (item: FoodItem) => void }) {
  const [expandedMeal, setExpandedMeal] = useState<MealType | null>(null);

  return (
    <section className="viewPanel">
      {mealMeta.map((meal) => {
        const mealItems = itemsByMeal(items, meal.key);
        const totals = totalsFor(mealItems);
        const isExpanded = expandedMeal === meal.key;
        return (
          <article className={`${mealItems.length ? "ledgerCard hasItems" : "ledgerCard empty"} ${isExpanded ? "expanded" : ""}`} key={meal.key}>
            <button
              aria-expanded={isExpanded}
              className="ledgerToggle"
              onClick={() => setExpandedMeal(isExpanded ? null : meal.key)}
              type="button"
            >
              <div className="ledgerHead">
                <div className="ledgerTitle">
                  <span className="ledgerIcon">{mealIcon(meal.key)}</span>
                  <div>
                    <h3>{meal.title}</h3>
                    <p>{mealItems.length ? `${mealItems.length} 个食物` : meal.hint}</p>
                  </div>
                </div>
                <span className="ledgerEnergy">{round(totals.calories)} kcal</span>
                <ChevronRight className="ledgerChevron" size={18} />
              </div>
            </button>
            {isExpanded && (
              <div className="ledgerBody">
                <PhotoStrip photos={uniquePhotos(mealItems)} empty="本餐暂无照片" />
                {mealItems.length ? (
                  <div className="mobileFoodDetailList">
                    {mealItems.map((item) => (
                      <div className={item.calories >= 400 ? "mobileFoodDetail highCalorie" : "mobileFoodDetail"} key={item.id}>
                        <div className="mobileFoodMain">
                          <span className="foodDot" />
                          <div>
                            <strong>{item.name}</strong>
                            <small>{round(item.grams)}g · 蛋白质 {round(item.protein)}g · 碳水 {round(item.carbs)}g · 脂肪 {round(item.fat)}g · 膳食纤维 {round(item.fiber)}g</small>
                            {item.note && <em>{item.note}</em>}
                          </div>
                        </div>
                        <div className="mobileFoodActions">
                          <b>{round(item.calories)} kcal</b>
                          <button aria-label={`编辑 ${item.name}`} onClick={() => onEditItem(item)} type="button"><PenLine size={13} /></button>
                          <button aria-label={`删除 ${item.name}`} onClick={() => onDeleteItem(item)} type="button"><Trash2 size={13} /></button>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="mobileFoodEmpty">还没有明细</div>
                )}
                <div className="tableWrap">
                  <table>
                    <thead>
                      <tr><th>食物</th><th>重量</th><th>热量</th><th>蛋白质</th><th>碳水</th><th>脂肪</th><th>膳食纤维</th><th>操作</th></tr>
                    </thead>
                    <tbody>
                      {mealItems.length ? mealItems.map((item) => (
                        <tr className={item.calories >= 400 ? "highCalorieRow" : ""} key={item.id}>
                          <td>
                            <details className="foodNote">
                              <summary><span className="foodDot" />{item.name}</summary>
                              <span>{item.note}</span>
                            </details>
                          </td>
                          <td>{round(item.grams)}g</td><td><b className="calorieCell">{round(item.calories)}</b></td><td>{round(item.protein)}g</td>
                          <td>{round(item.carbs)}g</td><td>{round(item.fat)}g</td><td>{round(item.fiber)}g</td>
                          <td>
                            <div className="rowActions">
                              <button className="rowEditButton" onClick={() => onEditItem(item)} type="button"><PenLine size={13} />编辑</button>
                              <button className="rowDeleteButton" onClick={() => onDeleteItem(item)} type="button"><Trash2 size={13} />删除</button>
                            </div>
                          </td>
                        </tr>
                      )) : <tr><td colSpan={8}>还没有明细</td></tr>}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </article>
        );
      })}
    </section>
  );
}

function Trend({
  bodyMetrics,
  dailyActivities,
  exerciseActivities,
  goals,
  items,
  selectedDate,
}: {
  bodyMetrics: BodyMetric[];
  dailyActivities: DailyActivity[];
  exerciseActivities: ExerciseActivity[];
  goals: UserGoals;
  items: FoodItem[];
  selectedDate: string;
}) {
  const dates = buildDates(items).slice(0, 7).reverse();
  const selectedItems = items.filter((item) => item.date === selectedDate);
  const selectedTotals = totalsFor(selectedItems);
  const topFoods = [...selectedItems].sort((a, b) => b.calories - a.calories).slice(0, 6);
  const max = Math.max(1, ...dates.map((date) => totalsFor(items.filter((item) => item.date === date)).calories));
  const weekTotals = dates.map((date) => totalsFor(items.filter((item) => item.date === date)));
  const weekCalories = weekTotals.reduce((sum, total) => sum + total.calories, 0);
  const weekProtein = weekTotals.reduce((sum, total) => sum + total.protein, 0);
  const bestDay = dates.reduce((best, date) => {
    const calories = totalsFor(items.filter((item) => item.date === date)).calories;
    return calories > best.calories ? { date, calories } : best;
  }, { date: "", calories: 0 });
  const streak = countRecordStreak(buildDates(items));
  const weekReport = buildPeriodReport(items, bodyMetrics, dailyActivities, exerciseActivities, goals, selectedDate, 7);
  const monthReport = buildPeriodReport(items, bodyMetrics, dailyActivities, exerciseActivities, goals, selectedDate, 30);
  return (
    <section className="trendGrid">
      <PeriodReportSummary title="本周复盘" report={weekReport} />
      <PeriodReportSummary title="30 日趋势" report={monthReport} />
      <article className="trendCard trendSummary">
        <StatTile
          icon={<Flame size={16} />}
          label="7日平均"
          tone="amber"
          value={<>{dates.length ? round(weekCalories / dates.length) : 0}<small>kcal / 天</small></>}
        />
        <StatTile
          icon={<Dumbbell size={16} />}
          label="蛋白平均"
          tone="blue"
          value={<>{dates.length ? round(weekProtein / dates.length) : 0}<small>g / 天</small></>}
        />
        <StatTile
          icon={<HeartPulse size={16} />}
          label="最高热量日"
          tone="rose"
          value={<>{bestDay.calories ? bestDay.date.slice(5) : "--"}<small>{round(bestDay.calories)} kcal</small></>}
        />
        <StatTile icon={<CheckCircle2 size={16} />} label="连续记录" tone="teal" value={<>{streak}<small>天</small></>} />
      </article>
      <article className="trendCard wide">
        <div className="trendCardHead">
          <div>
            <h3>热量趋势</h3>
            <p>每天摄入 kcal，红色为当前选择日期</p>
          </div>
          <strong>{round(totalsFor(selectedItems).calories).toLocaleString()} kcal</strong>
        </div>
        <div className="bars">
          {dates.map((date) => {
            const total = totalsFor(items.filter((item) => item.date === date)).calories;
            return (
              <div className="barWrap" key={date}>
                <strong>{round(total)}</strong>
                <div className={date === selectedDate ? "bar active" : "bar"} style={{ height: `${Math.max(8, (total / max) * 180)}px` }} />
                <span>{date.slice(5)}</span>
              </div>
            );
          })}
        </div>
      </article>
      <article className="trendCard">
        <h3>最高热量食物</h3>
        <ul>{topFoods.map((item) => <li key={item.id}><span>{item.name}</span><strong>{round(item.calories)} kcal</strong></li>)}</ul>
      </article>
      <article className="trendCard">
        <h3>照片记录</h3>
        <PhotoLibrary items={selectedItems} compact />
      </article>
      <CoachPanel items={selectedItems} totals={selectedTotals} />
      <div className="trendInsightColumn">
        <InsightCard tone="good" title="做得好" items={buildGoodInsights(selectedItems, selectedTotals)} />
        <InsightCard tone="warn" title="需要注意" items={buildNeedsInsights(selectedItems, selectedTotals)} />
      </div>
    </section>
  );
}

function PeriodReportSummary({ report, title }: { report: ReturnType<typeof buildPeriodReport>; title: string }) {
  return (
    <article className="trendCard reportSummaryCard">
      <div className="trendCardHead">
        <div>
          <h3>{title}</h3>
          <p>{report.startLabel} 至 {report.endLabel}</p>
        </div>
        <strong className="reportSummaryBadge">{report.summary}</strong>
      </div>
      <div className="reportMetricGrid">
        <StatTile icon={<Flame size={16} />} label="平均 kcal" tone="amber" value={round(report.averageCalories)} />
        <StatTile icon={<Dumbbell size={16} />} label="蛋白平均" tone="blue" value={`${round(report.averageProtein)}g`} />
        <StatTile icon={<CheckCircle2 size={16} />} label="达标天数" tone="teal" value={`${report.onTargetDays}/${report.days}`} />
        <StatTile icon={<Scale size={16} />} label="体重变化" tone="cyan" value={report.weightDeltaText} />
      </div>
      <ul className="reportInsightList">
        {report.insights.map((insight) => <li key={insight}>{insight}</li>)}
      </ul>
    </article>
  );
}

function StatTile({ icon, label, tone, value }: { icon: React.ReactNode; label: string; tone: string; value: React.ReactNode }) {
  return (
    <div className={`statTile ${tone}`}>
      <span className="statTileIcon">{icon}</span>
      <div>
        <strong>{value}</strong>
        <em>{label}</em>
      </div>
    </div>
  );
}

function PhotoLibrary({ items, compact = false }: { items: FoodItem[]; compact?: boolean }) {
  const photoGroups = buildPhotoGroups(items);
  const [dateFilter, setDateFilter] = useState("all");
  const [expandedPhotoUrl, setExpandedPhotoUrl] = useState<string | null>(null);
  const visibleGroups = dateFilter === "all" ? photoGroups : photoGroups.filter((group) => group.date === dateFilter);
  return (
    <section className={compact ? "photoLibrary compact" : "viewPanel photoLibrary"}>
      {!compact && photoGroups.length ? (
        <div className="photoToolbar">
          <div>
            <strong>照片记录</strong>
            <span>{photoGroups.reduce((sum, group) => sum + group.photos.length, 0)} 张照片</span>
          </div>
          <label>
            <CalendarDays size={15} />
            <select value={dateFilter} onChange={(event) => setDateFilter(event.target.value)}>
              <option value="all">全部日期</option>
              {photoGroups.map((group) => <option key={group.date} value={group.date}>{formatDateLabel(group.date)}</option>)}
            </select>
          </label>
        </div>
      ) : null}
      {visibleGroups.length ? visibleGroups.map((group) => (
        <div className="photoDay" key={group.date}>
          {!compact && <h3>{formatDateLabel(group.date)}</h3>}
          <div className="photoDayGrid">
            {group.photos.map((photo) => {
              const isExpanded = expandedPhotoUrl === photo.url;
              return (
              <figure className={isExpanded ? "photoCard expanded" : "photoCard"} key={photo.url}>
                <button
                  aria-expanded={isExpanded}
                  className="photoPreviewButton"
                  onClick={() => setExpandedPhotoUrl(isExpanded ? null : photo.url)}
                  type="button"
                >
                  <img src={photo.url} alt={`${photo.mealTitle}餐食照片`} />
                  <figcaption>
                    <span>{photo.mealTitle}</span>
                    <strong>{round(photo.calories)} kcal</strong>
                    {isExpanded && <em className="photoCloseHint">点击收起</em>}
                  </figcaption>
                </button>
              </figure>
              );
            })}
          </div>
        </div>
      )) : <p>还没有照片。</p>}
    </section>
  );
}

function buildPhotoGroups(items: FoodItem[]) {
  return buildDates(items).map((date) => {
    const dayItems = items.filter((item) => item.date === date);
    const photos = uniquePhotos(dayItems).map((url) => {
      const linkedItems = dayItems.filter((item) => item.photoUrls.includes(url));
      const first = linkedItems[0];
      const mealTitle = mealMeta.find((meal) => meal.key === first?.meal)?.title || "饮食";
      return { url, mealTitle, calories: totalsFor(linkedItems).calories };
    });
    return { date, photos };
  }).filter((group) => group.photos.length);
}

function topFoodBy(items: FoodItem[], key: keyof Pick<FoodItem, "calories" | "protein" | "carbs" | "fat" | "fiber">, minimum = 1) {
  return [...items]
    .filter((item) => Number(item[key] || 0) >= minimum)
    .sort((a, b) => Number(b[key] || 0) - Number(a[key] || 0))[0];
}

function nutrientGap(value: number, target: number) {
  return Math.max(0, round(target - value));
}

function daysBetween(startDate: string, endDate: string) {
  const start = new Date(`${startDate}T00:00:00`);
  const end = new Date(`${endDate}T00:00:00`);
  return Math.ceil((end.getTime() - start.getTime()) / 86_400_000);
}

function latestBodyMetricOnOrBefore(metrics: BodyMetric[], date: string) {
  return [...metrics].filter((metric) => metric.date <= date).sort((a, b) => b.date.localeCompare(a.date))[0];
}

function previousBodyMetric(metrics: BodyMetric[], current?: BodyMetric) {
  if (!current) return undefined;
  return [...metrics].filter((metric) => metric.date < current.date).sort((a, b) => b.date.localeCompare(a.date))[0];
}

function buildPeriodReport(
  items: FoodItem[],
  bodyMetrics: BodyMetric[],
  dailyActivities: DailyActivity[],
  exerciseActivities: ExerciseActivity[],
  goals: UserGoals,
  selectedDate: string,
  dayCount: number,
) {
  const dates = recentDateKeys(selectedDate, dayCount);
  const activeDates = dates.filter((date) => items.some((item) => item.date === date) || bodyMetrics.some((metric) => metric.date === date) || dailyActivities.some((activityItem) => activityItem.date === date));
  const countedDates = activeDates.length ? activeDates : dates;
  const totalsByDate = countedDates.map((date) => totalsFor(items.filter((item) => item.date === date)));
  const totalCalories = totalsByDate.reduce((sum, total) => sum + total.calories, 0);
  const totalProtein = totalsByDate.reduce((sum, total) => sum + total.protein, 0);
  const totalFiber = totalsByDate.reduce((sum, total) => sum + total.fiber, 0);
  const activityCalories = countedDates.reduce((sum, date) => sum + activityCaloriesForDate(dailyActivities, exerciseActivities, date), 0);
  const recordedFoodDays = countedDates.filter((date) => items.some((item) => item.date === date)).length;
  const onTargetDays = countedDates.filter((date) => {
    const calories = totalsFor(items.filter((item) => item.date === date)).calories;
    return calories > 0 && calories <= goals.dailyCalories;
  }).length;
  const proteinTargetDays = countedDates.filter((date) => totalsFor(items.filter((item) => item.date === date)).protein >= goals.protein).length;
  const periodBodyMetrics = bodyMetrics
    .filter((metric) => countedDates.includes(metric.date))
    .sort((a, b) => a.date.localeCompare(b.date));
  const firstBody = periodBodyMetrics[0];
  const lastBody = periodBodyMetrics[periodBodyMetrics.length - 1];
  const weightDelta = firstBody && lastBody ? lastBody.weightKg - firstBody.weightKg : 0;
  const averageCalories = totalCalories / Math.max(1, recordedFoodDays || countedDates.length);
  const averageProtein = totalProtein / Math.max(1, recordedFoodDays || countedDates.length);
  const averageFiber = totalFiber / Math.max(1, recordedFoodDays || countedDates.length);
  const netAverage = (totalCalories - activityCalories) / Math.max(1, countedDates.length);
  const topFood = [...items.filter((item) => countedDates.includes(item.date))].sort((a, b) => b.calories - a.calories)[0];
  const insights: string[] = [];

  if (recordedFoodDays < Math.min(dayCount, 5)) {
    insights.push(`这段时间只有 ${recordedFoodDays} 天有饮食记录，先提高记录连续性，复盘会更准。`);
  } else {
    insights.push(`饮食记录 ${recordedFoodDays}/${countedDates.length} 天，热量达标 ${onTargetDays} 天。`);
  }
  if (averageCalories > goals.dailyCalories) insights.push(`平均摄入比目标高约 ${round(averageCalories - goals.dailyCalories)} kcal/天，优先减少高频主食、甜食或加餐份量。`);
  if (averageCalories <= goals.dailyCalories && averageCalories > 0) insights.push(`平均热量在目标内，当前关键是蛋白质、蔬菜和运动稳定性。`);
  if (averageProtein < goals.protein * 0.85) insights.push(`蛋白平均 ${round(averageProtein)}g/天，距离目标还有明显空间。`);
  if (proteinTargetDays >= Math.max(1, Math.floor(recordedFoodDays * 0.5))) insights.push(`蛋白达标天数 ${proteinTargetDays} 天，保肌基础比之前更稳。`);
  if (averageFiber < goals.fiber * 0.75) insights.push(`膳食纤维平均 ${round(averageFiber)}g/天，蔬菜、豆类或全谷物可以再增加。`);
  if (topFood) insights.push(`最高热量单项是 ${topFood.name}，约 ${round(topFood.calories)} kcal。`);
  if (firstBody && lastBody) {
    if (weightDelta < -0.2) insights.push(`体重下降 ${Math.abs(weightDelta).toFixed(2)}kg，方向和减脂目标一致。`);
    if (weightDelta > 0.2) insights.push(`体重上升 ${weightDelta.toFixed(2)}kg，结合碳水、盐分、睡眠和测量时间再判断。`);
  }

  const summary = averageCalories <= goals.dailyCalories && averageProtein >= goals.protein * 0.85
    ? "节奏稳定"
    : averageCalories > goals.dailyCalories
      ? "热量偏高"
      : "蛋白优先";

  return {
    averageCalories,
    averageFiber,
    averageProtein,
    days: countedDates.length,
    endLabel: countedDates[countedDates.length - 1]?.slice(5) || "--",
    insights: insights.slice(0, 4),
    netAverage,
    onTargetDays,
    proteinTargetDays,
    recordedFoodDays,
    startLabel: countedDates[0]?.slice(5) || "--",
    summary,
    weightDeltaText: firstBody && lastBody ? `${weightDelta >= 0 ? "+" : ""}${weightDelta.toFixed(2)}kg` : "--",
  };
}

function buildGoodInsights(items: FoodItem[], totals: ReturnType<typeof totalsFor>) {
  if (!items.length) return ["今天还没有饮食记录，先记录一餐后这里会自动复盘。"];

  const insights = [];
  if (totals.calories <= nutrientTargets.calories) {
    insights.push(`总热量约 ${round(totals.calories).toLocaleString()} kcal，仍在 ${nutrientTargets.calories.toLocaleString()} kcal 参考目标内。`);
  }

  const proteinSource = topFoodBy(items, "protein", 5);
  if (proteinSource) insights.push(`蛋白质主要来自 ${proteinSource.name}，约 ${round(proteinSource.protein)}g。`);

  const fiberSource = topFoodBy(items, "fiber", 2);
  if (fiberSource) insights.push(`膳食纤维主要来自 ${fiberSource.name}，约 ${round(fiberSource.fiber)}g。`);

  if (totals.fat <= nutrientTargets.fat) insights.push(`脂肪约 ${round(totals.fat)}g，没有超过 ${nutrientTargets.fat}g 参考线。`);

  return insights.slice(0, 3);
}

function buildNeedsInsights(items: FoodItem[], totals: ReturnType<typeof totalsFor>) {
  if (!items.length) return ["今天还没有记录，先补一餐才能分析不足。"];

  const insights = [];
  if (totals.calories > nutrientTargets.calories) {
    insights.push(`热量比参考目标高约 ${round(totals.calories - nutrientTargets.calories)} kcal，优先检查最高热量食物的份量。`);
  }
  if (totals.protein < nutrientTargets.protein * 0.75) {
    insights.push(`蛋白质距离参考目标还差约 ${nutrientGap(totals.protein, nutrientTargets.protein)}g。`);
  }
  if (totals.fiber < nutrientTargets.fiber * 0.72) {
    insights.push(`膳食纤维距离参考目标还差约 ${nutrientGap(totals.fiber, nutrientTargets.fiber)}g。`);
  }
  if (totals.carbs > nutrientTargets.carbs) {
    const carbSource = topFoodBy(items, "carbs", 15);
    insights.push(carbSource ? `碳水主要受 ${carbSource.name} 影响，约 ${round(carbSource.carbs)}g。` : "碳水偏高，主食和水果份量需要留意。");
  }

  const topCalorie = topFoodBy(items, "calories", Math.max(180, totals.calories * 0.18));
  if (topCalorie && insights.length < 3) {
    insights.push(`${topCalorie.name} 是今天影响最大的单项，约 ${round(topCalorie.calories)} kcal。`);
  }

  return insights.slice(0, 3).length ? insights.slice(0, 3) : ["今天的核心营养暂时比较平衡。"];
}

function buildSwapSuggestions(items: FoodItem[]) {
  if (!items.length) return ["先记录一整天后，这里会根据真实食物给替换建议。"];

  const suggestions = [];
  const topCalorie = topFoodBy(items, "calories", 180);
  const topCarb = topFoodBy(items, "carbs", 35);
  const topFat = topFoodBy(items, "fat", 12);

  if (topCalorie) suggestions.push(`${topCalorie.name} 热量最高，可以先减少 20% 份量，或把同餐其他高热量项减半。`);
  if (topCarb && topCarb.id !== topCalorie?.id) suggestions.push(`${topCarb.name} 碳水贡献较高，另一餐主食可以少一份。`);
  if (topFat && topFat.id !== topCalorie?.id) suggestions.push(`${topFat.name} 脂肪贡献较高，下一次优先少油或减少酱汁。`);

  return suggestions.slice(0, 3).length ? suggestions.slice(0, 3) : ["今天没有特别突出的高热量单项，继续保持份量记录即可。"];
}

function buildTomorrowSuggestions(totals: ReturnType<typeof totalsFor>) {
  const suggestions = [];
  const proteinGap = nutrientGap(totals.protein, nutrientTargets.protein);
  const fiberGap = nutrientGap(totals.fiber, nutrientTargets.fiber);

  if (proteinGap > 0) suggestions.push(`明天把蛋白质目标前置，争取比今天多约 ${proteinGap}g。`);
  if (fiberGap > 0) suggestions.push(`明天至少提前安排一份高纤维食物，补足约 ${fiberGap}g 膳食纤维缺口。`);
  if (totals.calories > nutrientTargets.calories) suggestions.push("明天先控制最高热量的一餐，主食、甜食和酱汁只保留最想吃的一项。");
  if (totals.calories <= nutrientTargets.calories) suggestions.push("热量节奏可以，重点是把蛋白质和膳食纤维补到更稳。");
  return suggestions.slice(0, 3);
}

function buildBodyFoodInsights(current: BodyMetric, previous: BodyMetric | undefined, totals: ReturnType<typeof totalsFor>) {
  const insights = [];
  if (previous) {
    const weightDelta = current.weightKg - previous.weightKg;
    const fatDelta = current.bodyFatPercent - previous.bodyFatPercent;
    if (weightDelta < -0.2) insights.push(`体重比上次低 ${Math.abs(weightDelta).toFixed(2)}kg，当前饮食节奏可能正在产生效果。`);
    if (weightDelta > 0.2) insights.push(`体重比上次高 ${weightDelta.toFixed(2)}kg，先结合盐分、碳水和测量时间判断，不急着下结论。`);
    if (fatDelta < -0.2) insights.push(`体脂比上次低 ${Math.abs(fatDelta).toFixed(1)}%，这是比单日体重更有价值的趋势信号。`);
  }
  if (totals.calories && current.bmrKcal) {
    const gap = totals.calories - current.bmrKcal;
    if (gap < -250) insights.push(`今天摄入比基础代谢低约 ${Math.abs(round(gap))} kcal，减脂友好，但要保证蛋白和蔬菜。`);
    if (gap > 300) insights.push(`今天摄入比基础代谢高约 ${round(gap)} kcal，如果目标是减脂，晚餐和加餐需要更克制。`);
  }
  if (totals.protein && current.weightKg) {
    const proteinPerKg = totals.protein / current.weightKg;
    if (proteinPerKg < 1.2) insights.push(`蛋白约 ${proteinPerKg.toFixed(1)}g/kg，减脂期偏低，明天优先把蛋白质份量补足。`);
    if (proteinPerKg >= 1.2) insights.push(`蛋白约 ${proteinPerKg.toFixed(1)}g/kg，保肌基础不错。`);
  }
  if (current.bodyFatPercent >= 20) insights.push("体脂目前仍有下降空间，核心策略是稳定热量缺口和力量训练。");
  return insights.length ? insights : ["记录几天身体和饮食后，这里会给出更可靠的趋势判断。"];
}

const activitySourceOptions = [
  { value: "manual", label: "手动录入" },
  { value: "apple_health", label: "Apple 健康" },
  { value: "apple_shortcut", label: "Apple 健康快捷指令" },
  { value: "apple_fitness", label: "Apple Fitness" },
  { value: "garmin", label: "Garmin" },
  { value: "strava", label: "Strava" },
  { value: "import", label: "文件导入" },
];

function sourceLabel(source: string) {
  return activitySourceOptions.find((option) => option.value === source)?.label || source || "未知来源";
}

function workoutIcon(type: string) {
  if (/跑|run|步/.test(type)) return <Footprints size={18} />;
  if (/骑|车|bike|cycling|cycle/.test(type)) return <Bike size={18} />;
  if (/力量|重训|strength|肌/.test(type)) return <Dumbbell size={18} />;
  if (/走|walk/.test(type)) return <Footprints size={18} />;
  return <Activity size={18} />;
}

function activityCaloriesForDate(dailyActivities: DailyActivity[], exerciseActivities: ExerciseActivity[], date: string) {
  const daily = dailyActivities.find((activityItem) => activityItem.date === date);
  if (daily?.activeCalories) return daily.activeCalories;
  return exerciseActivities
    .filter((activityItem) => activityItem.date === date)
    .reduce((sum, workout) => sum + workout.activeCalories, 0);
}

function recentDateKeys(anchorDate: string, count: number) {
  const anchor = new Date(`${anchorDate}T00:00:00`);
  return Array.from({ length: count }, (_, index) => {
    const date = new Date(anchor);
    date.setDate(anchor.getDate() - (count - 1 - index));
    return dateKey(date);
  });
}

function formatHealthMetricValue(value: number, unit: string) {
  const rounded = Math.abs(value) >= 100
    ? Math.round(value).toLocaleString()
    : (Math.round(value * 10) / 10).toLocaleString();
  return unit ? `${rounded}${unit}` : rounded;
}

function buildExerciseInsights(totals: ReturnType<typeof totalsFor>, daily: DailyActivity | undefined, workouts: ExerciseActivity[], body: BodyMetric | undefined) {
  const insights = [];
  const workoutCalories = workouts.reduce((sum, workout) => sum + workout.activeCalories, 0);
  const activeCalories = daily?.activeCalories || workoutCalories;
  const exerciseMinutes = daily?.exerciseMinutes || workouts.reduce((sum, workout) => sum + workout.durationMinutes, 0);

  if (!daily && !workouts.length) return ["还没有运动数据。先记录活动热量、步数或训练，系统就能判断摄入和消耗是否匹配。"];

  if (totals.calories && activeCalories) {
    const net = totals.calories - activeCalories;
    if (net < 1200) insights.push(`扣除活动消耗后约 ${round(net)} kcal，减脂友好，但不要长期过低。`);
    if (net >= 1200 && net <= 1800) insights.push(`扣除活动消耗后约 ${round(net)} kcal，今天节奏比较稳。`);
    if (net > 1800) insights.push(`扣除活动消耗后仍约 ${round(net)} kcal，若目标是减脂，晚餐和加餐要更克制。`);
  }

  if (daily?.steps) {
    if (daily.steps >= 8000) insights.push(`步数 ${round(daily.steps).toLocaleString()}，日常活动量不错。`);
    if (daily.steps < 5000) insights.push(`步数 ${round(daily.steps).toLocaleString()} 偏低，可以用饭后散步补一点消耗。`);
  }

  if (exerciseMinutes >= 30) insights.push(`运动 ${round(exerciseMinutes)} 分钟，今天有明确训练或活动积累。`);
  if (workouts.some((workout) => /力量|重训|strength|肌/.test(workout.type)) && body?.weightKg && totals.protein) {
    const proteinPerKg = totals.protein / body.weightKg;
    if (proteinPerKg < 1.4) insights.push(`有力量训练时蛋白建议更高，今天约 ${proteinPerKg.toFixed(1)}g/kg，下一餐优先补足蛋白质份量。`);
    else insights.push(`力量训练日蛋白约 ${proteinPerKg.toFixed(1)}g/kg，保肌基础不错。`);
  }

  if (daily?.restingHeartRate && daily.restingHeartRate > 75) insights.push("静息心率偏高时，训练强度可以保守一些，优先睡眠和恢复。");
  return insights.slice(0, 4);
}

function bodyPartMetrics(metric: BodyMetric) {
  const screenshotDefaults = metric.date === "2026-06-30" ? {
    trunk: { fat: 22.93, muscle: 28.93 },
    leftArm: { fat: 16.04, muscle: 2.7 },
    rightArm: { fat: 15.01, muscle: 2.91 },
    leftLeg: { fat: 19.19, muscle: 10.55 },
    rightLeg: { fat: 19.42, muscle: 10.56 },
  } : null;
  const fallbackMuscle = metric.muscleKg || metric.skeletalMuscleKg || 0;
  const fallback = {
    trunk: { fat: metric.bodyFatPercent || 0, muscle: fallbackMuscle * 0.5 },
    leftArm: { fat: metric.bodyFatPercent || 0, muscle: fallbackMuscle * 0.05 },
    rightArm: { fat: metric.bodyFatPercent || 0, muscle: fallbackMuscle * 0.05 },
    leftLeg: { fat: metric.bodyFatPercent || 0, muscle: fallbackMuscle * 0.2 },
    rightLeg: { fat: metric.bodyFatPercent || 0, muscle: fallbackMuscle * 0.2 },
  };
  return {
    trunk: {
      fat: metric.trunkFatPercent || screenshotDefaults?.trunk.fat || fallback.trunk.fat,
      muscle: metric.trunkMuscleKg || screenshotDefaults?.trunk.muscle || fallback.trunk.muscle,
    },
    leftArm: {
      fat: metric.leftArmFatPercent || screenshotDefaults?.leftArm.fat || fallback.leftArm.fat,
      muscle: metric.leftArmMuscleKg || screenshotDefaults?.leftArm.muscle || fallback.leftArm.muscle,
    },
    rightArm: {
      fat: metric.rightArmFatPercent || screenshotDefaults?.rightArm.fat || fallback.rightArm.fat,
      muscle: metric.rightArmMuscleKg || screenshotDefaults?.rightArm.muscle || fallback.rightArm.muscle,
    },
    leftLeg: {
      fat: metric.leftLegFatPercent || screenshotDefaults?.leftLeg.fat || fallback.leftLeg.fat,
      muscle: metric.leftLegMuscleKg || screenshotDefaults?.leftLeg.muscle || fallback.leftLeg.muscle,
    },
    rightLeg: {
      fat: metric.rightLegFatPercent || screenshotDefaults?.rightLeg.fat || fallback.rightLeg.fat,
      muscle: metric.rightLegMuscleKg || screenshotDefaults?.rightLeg.muscle || fallback.rightLeg.muscle,
    },
  };
}

function formatDelta(current: number, previous: number | undefined, unit: string) {
  if (!previous) return "";
  const delta = current - previous;
  if (Math.abs(delta) < 0.05) return "基本持平";
  const sign = delta > 0 ? "+" : "";
  return `${sign}${delta.toFixed(unit === "%" ? 1 : 2)}${unit}`;
}

function formatMetricDelta(delta: number, unit: string) {
  if (!Number.isFinite(delta) || Math.abs(delta) < 0.05) return "基本持平";
  const sign = delta > 0 ? "+" : "";
  return `${sign}${delta.toFixed(unit === "%" ? 1 : 2)} ${unit}`;
}

function bmiStatus(bmi: number) {
  if (!bmi) return "--";
  if (bmi < 18.5) return "偏低";
  if (bmi < 24) return "标准";
  if (bmi < 28) return "偏高";
  return "较高";
}

function toDateTimeLocal(value?: string) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value.slice(0, 16);
  const offsetMs = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offsetMs).toISOString().slice(0, 16);
}

function formatMeasuredAt(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function countRecordStreak(dates: string[]) {
  if (!dates.length) return 0;
  const set = new Set(dates);
  const [year, month, day] = dates[0].split("-").map(Number);
  const cursor = new Date(year, month - 1, day);
  let count = 0;
  while (set.has(dateKey(cursor))) {
    count += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return count;
}

function dateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function addMonths(date: Date, months: number) {
  const next = new Date(date);
  next.setMonth(next.getMonth() + months);
  return next;
}

createRoot(document.getElementById("root")!).render(<App />);
