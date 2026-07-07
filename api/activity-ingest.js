import { createClient } from "@supabase/supabase-js";

function json(res, status, payload) {
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

function normalizeError(error) {
  if (error instanceof Error) return { message: error.message, name: error.name };
  if (error && typeof error === "object") {
    return {
      message: error.message || error.error || JSON.stringify(error),
      code: error.code,
      details: error.details,
      hint: error.hint,
      status: error.status,
    };
  }
  return { message: String(error) };
}

async function readJson(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string") return parseRequestBody(req.body, req.headers["content-type"]);
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = Buffer.concat(chunks).toString("utf8");
  return parseRequestBody(body, req.headers["content-type"]);
}

function parseRequestBody(body, contentTypeValue) {
  if (!body) return {};
  const contentType = String(contentTypeValue || "");
  if (contentType.includes("application/x-www-form-urlencoded")) {
    return Object.fromEntries(new URLSearchParams(body).entries());
  }
  try {
    return JSON.parse(body);
  } catch {
    if (body.includes("=")) return Object.fromEntries(new URLSearchParams(body).entries());
    return { text: body };
  }
}

function requireBearer(req) {
  const token = process.env.DIARY_INGEST_TOKEN;
  if (!token) return { ok: false, status: 500, message: "DIARY_INGEST_TOKEN is not configured." };
  const url = new URL(req.url || "/", "https://diet-cloud.vercel.app");
  const header = String(req.headers.authorization || "");
  const bearer = header.match(/^Bearer\s+(.+)$/i)?.[1] || "";
  const provided = cleanToken(
    bearer
      || req.headers["x-diary-token"]
      || url.searchParams.get("token")
      || url.searchParams.get("diaryToken")
      || url.searchParams.get("apiKey")
      || url.searchParams.get("key")
      || "",
  );
  if (provided !== token) return { ok: false, status: 401, message: "Unauthorized." };
  return { ok: true };
}

function cleanToken(value) {
  return String(Array.isArray(value) ? value[0] : value)
    .trim()
    .replace(/^DIARY_INGEST_TOKEN\s*=\s*/i, "")
    .replace(/^Bearer\s+/i, "")
    .replace(/^["']|["']$/g, "")
    .trim();
}

function truthy(value) {
  return value === true || String(value).toLowerCase() === "true" || String(value) === "1";
}

async function resolveUserId(supabase, payload) {
  if (payload.userId || process.env.DIARY_USER_ID) return payload.userId || process.env.DIARY_USER_ID;
  const email = payload.userEmail || process.env.DIARY_USER_EMAIL;
  if (!email) throw new Error("DIARY_USER_ID or DIARY_USER_EMAIL is required.");

  let page = 1;
  while (page < 20) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const user = data.users.find((item) => item.email?.toLowerCase() === email.toLowerCase());
    if (user) return user.id;
    if (!data.users.length) break;
    page += 1;
  }
  throw new Error(`No Supabase user found for ${email}.`);
}

function toDateTime(value, date) {
  if (!value) return `${date}T00:00:00`;
  return value.length === 16 ? `${value}:00` : value;
}

function todayKey() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function normalizeDateKey(value) {
  if (!value) return todayKey();
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value.toISOString().slice(0, 10);
  const text = String(value).trim();
  const iso = text.match(/(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
  if (iso) return `${iso[1]}-${iso[2].padStart(2, "0")}-${iso[3].padStart(2, "0")}`;
  const zh = text.match(/(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日/);
  if (zh) return `${zh[1]}-${zh[2].padStart(2, "0")}-${zh[3].padStart(2, "0")}`;
  return todayKey();
}

function toNumber(value) {
  if (Array.isArray(value)) return value.reduce((sum, item) => sum + toNumber(item), 0);
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") {
    const text = value.trim();
    const unitMatches = [...text.matchAll(/(-?\d+(?:,\d{3})*(?:\.\d+)?)\s*(kcal|千卡|卡路里|步|steps?|秒|sec|seconds?|分钟|分鐘|分|minutes?|min|小时|小時|hours?|hrs?|hr|km|公里|米|m|层|層|bpm|次\/分|ms|毫秒|%|kg|公斤)/gi)];
    const token = unitMatches.length ? unitMatches[unitMatches.length - 1][1] : text.replace(/,/g, "").replace(/[^\d.-]/g, "");
    const parsed = Number(token.replace(/,/g, ""));
    return Number.isFinite(parsed) ? parsed : 0;
  }
  if (value && typeof value === "object") {
    return toNumber(value.value ?? value.quantity ?? value.total ?? value.amount ?? 0);
  }
  return 0;
}

function pick(item, keys) {
  for (const key of keys) {
    if (item[key] !== undefined && item[key] !== null && item[key] !== "") return item[key];
  }
  return undefined;
}

function firstNumber(item, keys, fallback = 0) {
  const value = pick(item, keys);
  return value === undefined ? fallback : toNumber(value);
}

function durationMinutes(value) {
  if (Array.isArray(value)) return value.reduce((sum, item) => sum + durationMinutes(item), 0);
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (value && typeof value === "object") return durationMinutes(value.value ?? value.quantity ?? value.total ?? value.amount ?? 0);
  const text = String(value || "").toLowerCase();
  const number = toNumber(text);
  if (!number) return 0;
  if (/秒|sec|second|(^|\s)s($|\s)/i.test(text)) return number / 60;
  if (/小时|小時|hour|hr|(^|\s)h($|\s)/i.test(text)) return number * 60;
  return number;
}

function durationHours(value) {
  if (Array.isArray(value)) return value.reduce((sum, item) => sum + durationHours(item), 0);
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (value && typeof value === "object") return durationHours(value.value ?? value.quantity ?? value.total ?? value.amount ?? 0);
  const text = String(value || "").toLowerCase();
  const number = toNumber(text);
  if (!number) return 0;
  if (/秒|sec|second|(^|\s)s($|\s)/i.test(text)) return number / 3600;
  if (/分钟|分鐘|minute|min|(^|\s)m($|\s)/i.test(text)) return number / 60;
  return number > 24 ? number / 60 : number;
}

function normalizeDistanceKm(item) {
  const explicitKm = pick(item, ["distanceKm", "distance_km", "公里", "距离公里"]);
  if (explicitKm !== undefined) return toNumber(explicitKm);

  const meterValue = pick(item, ["distanceMeters", "distance_meters", "步行+跑步距离", "步行 + 跑步距离", "步行跑步距离", "距离", "距离总计", "米", "距离米", "HKQuantityTypeIdentifierDistanceWalkingRunning"]);
  const distance = toNumber(meterValue);
  return distance > 80 ? distance / 1000 : distance;
}

function normalizeStandHours(item) {
  const explicitHours = pick(item, ["standHours", "stand_hours", "站立小时"]);
  if (explicitHours !== undefined) return toNumber(explicitHours);

  const standValue = pick(item, ["standMinutes", "stand_minutes", "站立分钟", "站立时间", "Apple 站立时间", "HKQuantityTypeIdentifierAppleStandTime", "HKCategoryTypeIdentifierAppleStandHour"]);
  return standValue === undefined ? 0 : durationHours(standValue);
}

function normalizeSleepMinutes(item) {
  const explicitMinutes = pick(item, ["sleepMinutes", "sleep_minutes", "睡眠分钟", "睡眠时间"]);
  if (explicitMinutes !== undefined) return toNumber(explicitMinutes);

  const hours = pick(item, ["sleepHours", "sleep_hours", "睡眠小时", "睡眠"]);
  const sleep = toNumber(hours);
  return sleep > 0 && sleep <= 24 ? sleep * 60 : sleep;
}

function normalizeShortcutItem(item) {
  const activeCalories = firstNumber(item, [
    "activeCalories",
    "active_calories",
    "activityCalories",
    "moveCalories",
    "活动能量",
    "HKQuantityTypeIdentifierActiveEnergyBurned",
    "活动能量总计",
    "活动消耗",
    "活动卡路里",
    "运动消耗",
    "活跃能量",
    "动态能量",
  ]);
  const basalCalories = firstNumber(item, [
    "basalCalories",
    "restingCalories",
    "basal_calories",
    "resting_calories",
    "静息能量",
    "HKQuantityTypeIdentifierBasalEnergyBurned",
    "静息能量总计",
    "基础能量",
    "基础代谢能量",
  ]);

  return {
    date: normalizeDateKey(pick(item, ["date", "activityOn", "activity_on", "日期", "开始日期", "startDate", "start_date"])),
    source: pick(item, ["source", "来源"]) || "apple_shortcut",
    steps: firstNumber(item, ["steps", "stepCount", "step_count", "步数", "步数总计", "HKQuantityTypeIdentifierStepCount"]),
    activeCalories,
    basalCalories,
    totalCalories: firstNumber(item, ["totalCalories", "total_calories", "总消耗", "总热量"], activeCalories + basalCalories),
    exerciseMinutes: durationMinutes(pick(item, [
      "exerciseMinutes",
      "exercise_minutes",
      "workoutMinutes",
      "workout_minutes",
      "运动时间",
      "Apple 运动时间",
      "HKQuantityTypeIdentifierAppleExerciseTime",
      "锻炼时间",
      "运动分钟",
      "锻炼分钟",
      "运动时间分钟",
    ]) || 0),
    standHours: normalizeStandHours(item),
    distanceKm: normalizeDistanceKm(item),
    floors: firstNumber(item, ["floors", "flightsClimbed", "flights_climbed", "已爬楼层", "爬楼", "楼层", "楼层总计", "HKQuantityTypeIdentifierFlightsClimbed"]),
    restingHeartRate: firstNumber(item, [
      "restingHeartRate",
      "resting_heart_rate",
      "静息心率",
      "静息心率平均值",
      "静息心率平均",
      "HKQuantityTypeIdentifierRestingHeartRate",
    ]),
    hrvMs: firstNumber(item, [
      "hrvMs",
      "hrv_ms",
      "heartRateVariability",
      "heart_rate_variability",
      "心率变异性",
      "心率变异性SDNN",
      "心率变异性平均值",
      "HRV",
      "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
    ]),
    sleepMinutes: normalizeSleepMinutes(item),
    rawMetrics: item.rawMetrics || item.raw_metrics || {},
    note: pick(item, ["note", "备注"]) || "来自 iPhone 快捷指令自动同步。",
  };
}

function metric(label, category, value, unit) {
  return { label, category, value: Math.round(toNumber(value) * 100) / 100, unit };
}

function shortcutRawMetrics(item) {
  return {
    ...(item.rawMetrics || {}),
    HKQuantityTypeIdentifierStepCount: metric("步数", "活动", item.steps, "步"),
    HKQuantityTypeIdentifierActiveEnergyBurned: metric("活动能量", "活动", item.activeCalories, "kcal"),
    HKQuantityTypeIdentifierBasalEnergyBurned: metric("静息能量", "活动", item.basalCalories || item.restingCalories || 0, "kcal"),
    HKQuantityTypeIdentifierAppleExerciseTime: metric("运动时间", "活动", item.exerciseMinutes, "分钟"),
    HKQuantityTypeIdentifierAppleStandTime: metric("站立时间", "活动", item.standHours, "小时"),
    HKQuantityTypeIdentifierDistanceWalkingRunning: metric("步行+跑步距离", "活动", item.distanceKm, "km"),
    HKQuantityTypeIdentifierFlightsClimbed: metric("爬楼", "活动", item.floors, "层"),
    HKQuantityTypeIdentifierRestingHeartRate: metric("静息心率", "心脏", item.restingHeartRate, "bpm"),
    HKQuantityTypeIdentifierHeartRateVariabilitySDNN: metric("HRV", "心脏", item.hrvMs, "ms"),
    HKCategoryTypeIdentifierSleepAnalysis: metric("睡眠", "睡眠", item.sleepMinutes, "分钟"),
  };
}

function normalizeDailyActivities(payload) {
  if (Array.isArray(payload)) {
    return payload.map((item) => {
      const normalized = normalizeShortcutItem(item);
      return {
        ...normalized,
        rawMetrics: Object.keys(normalized.rawMetrics || {}).length ? normalized.rawMetrics : shortcutRawMetrics(normalized),
      };
    });
  }
  if (Array.isArray(payload.dailyActivities)) {
    return payload.dailyActivities.map((item) => {
      const normalized = normalizeShortcutItem(item);
      return {
        ...normalized,
        rawMetrics: Object.keys(normalized.rawMetrics || {}).length ? normalized.rawMetrics : shortcutRawMetrics(normalized),
      };
    });
  }
  const item = payload.dailyActivity || payload.activity || payload;
  if (!item || typeof item !== "object") return [];
  const normalized = normalizeShortcutItem(item);
  return [{
    ...normalized,
    rawMetrics: shortcutRawMetrics(normalized),
  }];
}

function payloadFromQuery(req) {
  const url = new URL(req.url || "/", "https://diet-cloud.vercel.app");
  return Object.fromEntries(url.searchParams.entries());
}

function isIngestPayload(payload) {
  return [
    "write",
    "ingest",
    "dailyActivity",
    "activity",
    "steps",
    "stepCount",
    "步数",
    "HKQuantityTypeIdentifierStepCount",
    "activeCalories",
    "活动能量",
    "HKQuantityTypeIdentifierActiveEnergyBurned",
    "exerciseMinutes",
    "运动时间",
    "HKQuantityTypeIdentifierAppleExerciseTime",
    "standHours",
    "站立时间",
    "HKQuantityTypeIdentifierAppleStandTime",
  ].some((key) => payload[key] !== undefined);
}

function chunkArray(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) chunks.push(items.slice(index, index + size));
  return chunks;
}

async function upsertDailyActivities(supabase, userId, dailyActivities = []) {
  let count = 0;
  const imported = [];
  for (const chunk of chunkArray(dailyActivities, 500)) {
    const rows = chunk.map((item) => ({
      user_id: userId,
      activity_on: item.date,
      source: item.source || "apple_shortcut",
      steps: toNumber(item.steps),
      active_calories: toNumber(item.activeCalories),
      total_calories: toNumber(item.totalCalories),
      exercise_minutes: toNumber(item.exerciseMinutes),
      stand_hours: toNumber(item.standHours),
      distance_km: toNumber(item.distanceKm),
      floors: toNumber(item.floors),
      resting_heart_rate: toNumber(item.restingHeartRate),
      hrv_ms: toNumber(item.hrvMs),
      sleep_minutes: toNumber(item.sleepMinutes),
      raw_metrics: item.rawMetrics || {},
      note: item.note || null,
    }));
    const { error } = await supabase.from("daily_activities").upsert(rows, { onConflict: "user_id,activity_on,source" });
    if (error) throw error;
    count += rows.length;
    imported.push(...rows.map((row) => ({
      date: row.activity_on,
      source: row.source,
      steps: row.steps,
      activeCalories: row.active_calories,
      exerciseMinutes: row.exercise_minutes,
      standHours: row.stand_hours,
      distanceKm: row.distance_km,
      floors: row.floors,
      restingHeartRate: row.resting_heart_rate,
      hrvMs: row.hrv_ms,
      sleepMinutes: row.sleep_minutes,
    })));
  }
  return { count, imported };
}

function diagnosticWarnings(dailyActivities) {
  const warnings = [];
  if (!dailyActivities.length) warnings.push("没有解析到 dailyActivity / activity / dailyActivities 数据。");
  for (const item of dailyActivities) {
    if (!hasUsefulActivityData(item)) warnings.push(`${item.date} 解析到的数据全是 0，快捷指令没有把步数、活动热量、运动时间、站立时间或距离的数值传过来。`);
    if (String(item.date || "").length !== 10) warnings.push(`${item.date || "(空日期)"} 日期格式异常，建议用 yyyy-MM-dd。`);
  }
  return warnings;
}

function hasUsefulActivityData(item) {
  return [
    item.steps,
    item.activeCalories,
    item.exerciseMinutes,
    item.standHours,
    item.distanceKm,
    item.floors,
    item.restingHeartRate,
    item.hrvMs,
    item.sleepMinutes,
  ].some((value) => Math.abs(toNumber(value)) > 0);
}

function receivedSummary(payload) {
  const copy = { ...payload };
  for (const key of ["token", "diaryToken", "apiKey", "key"]) {
    if (copy[key]) copy[key] = "[hidden]";
  }
  return {
    keys: Object.keys(payload),
    values: copy,
  };
}

async function listRecentDailyActivities(supabase, userId, req) {
  const url = new URL(req.url || "/", "https://diet-cloud.vercel.app");
  const date = url.searchParams.get("date");
  const limit = Math.min(20, Math.max(1, Number(url.searchParams.get("limit") || 8)));
  let query = supabase
    .from("daily_activities")
    .select("activity_on,source,steps,active_calories,total_calories,exercise_minutes,stand_hours,distance_km,floors,resting_heart_rate,hrv_ms,sleep_minutes,note,created_at")
    .eq("user_id", userId)
    .order("activity_on", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(limit);

  if (date) query = query.eq("activity_on", normalizeDateKey(date));
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

async function upsertWorkouts(supabase, userId, workouts = []) {
  let count = 0;
  for (const chunk of chunkArray(workouts, 500)) {
    const rows = chunk.map((item) => ({
      user_id: userId,
      activity_on: item.date,
      started_at: toDateTime(item.startedAt, item.date),
      source: item.source || "shortcut",
      external_id: item.externalId || `shortcut-${item.date}-${item.type || "workout"}-${item.startedAt || ""}`,
      type: item.type || "其他",
      title: item.title || item.type || "运动",
      duration_minutes: Number(item.durationMinutes || 0),
      distance_km: Number(item.distanceKm || 0),
      active_calories: Number(item.activeCalories || 0),
      avg_heart_rate: Number(item.avgHeartRate || 0),
      max_heart_rate: Number(item.maxHeartRate || 0),
      elevation_gain_m: Number(item.elevationGainM || 0),
      note: item.note || null,
    }));
    const { error } = await supabase.from("exercise_activities").upsert(rows, { onConflict: "user_id,source,external_id" });
    if (error) throw error;
    count += rows.length;
  }
  return count;
}

async function deleteDiagnosticRows(supabase, userId, payload) {
  const requestedSource = String(payload.deleteSource || "_diagnostic");
  const source = requestedSource.startsWith("_") || requestedSource === "apple_shortcut"
    ? requestedSource
    : "_diagnostic";
  let query = supabase
    .from("daily_activities")
    .delete()
    .eq("user_id", userId)
    .eq("source", source);

  const date = payload.date || payload.activityOn || payload.activity_on;
  if (date) query = query.eq("activity_on", date);
  if (source === "apple_shortcut" && !date) throw new Error("Deleting apple_shortcut requires a date.");

  const { error } = await query;
  if (error) throw error;
  return true;
}

export default async function handler(req, res) {
  if (req.method === "OPTIONS") {
    res.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
    res.setHeader("access-control-allow-headers", "authorization, content-type");
    return json(res, 204, {});
  }

  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("allow", "GET, POST");
    return json(res, 405, { error: "Method not allowed." });
  }

  const auth = requireBearer(req);
  if (!auth.ok) return json(res, auth.status, { error: auth.message });

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return json(res, 500, { error: "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required." });
  }

  try {
    const payload = req.method === "POST" ? await readJson(req) : payloadFromQuery(req);
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const userId = await resolveUserId(supabase, payload);
    if (req.method === "GET" && !isIngestPayload(payload)) {
      const rows = await listRecentDailyActivities(supabase, userId, req);
      return json(res, 200, { ok: true, count: rows.length, dailyActivities: rows });
    }
    const normalizedDailyActivities = normalizeDailyActivities(payload);
    if (truthy(payload.dryRun) || truthy(payload.debug) || payload.mode === "diagnostic") {
      return json(res, 200, {
        ok: true,
        dryRun: true,
        payloadKeys: Object.keys(payload),
        received: receivedSummary(payload),
        dailyActivities: normalizedDailyActivities,
        warnings: diagnosticWarnings(normalizedDailyActivities),
      });
    }
    if (truthy(payload.deleteDiagnostic) || payload.deleteSource) {
      await deleteDiagnosticRows(supabase, userId, payload);
      return json(res, 200, { ok: true, deletedDiagnostic: true, deletedSource: payload.deleteSource || "_diagnostic" });
    }
    const warnings = diagnosticWarnings(normalizedDailyActivities);
    if (!truthy(payload.allowZero) && normalizedDailyActivities.some((item) => !hasUsefulActivityData(item))) {
      return json(res, 400, {
        ok: false,
        error: "快捷指令传来的运动数据全是 0，已拒绝写入，避免覆盖正确数据。",
        received: receivedSummary(payload),
        dailyActivities: normalizedDailyActivities,
        warnings,
        hint: "请检查 URL 里是否真的包含 steps、activeCalories、exerciseMinutes、standHours、distanceKm，并且这些参数后面是数字，不是空变量。",
      });
    }
    const dailyResult = await upsertDailyActivities(supabase, userId, normalizedDailyActivities);
    const workoutsImported = await upsertWorkouts(supabase, userId, payload.workouts || []);
    return json(res, 200, { ok: true, dailyImported: dailyResult.count, dailyActivities: dailyResult.imported, workoutsImported, warnings, received: receivedSummary(payload) });
  } catch (error) {
    const normalized = normalizeError(error);
    return json(res, 500, { error: normalized.message, details: normalized });
  }
}
