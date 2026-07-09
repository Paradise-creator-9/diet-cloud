import { createClient } from "@supabase/supabase-js";
import type { BodyMetric, DailyActivity, ExerciseActivity, FoodItem, MealType } from "./types";
import { compressPhotosForUpload } from "./utils";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;
const storageBucket = import.meta.env.VITE_SUPABASE_STORAGE_BUCKET as string | undefined;

export const isCloudConfigured = Boolean(supabaseUrl && supabaseAnonKey);
export const configuredStorageBucket = storageBucket || "meal-photos";

export const supabase = isCloudConfigured
  ? createClient(supabaseUrl!, supabaseAnonKey!, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null;

type MealRow = {
  id: string;
  eaten_on: string;
  meal: MealType;
  name: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  note: string | null;
  photo_urls: string[] | null;
  created_at: string;
};

type BodyMetricRow = {
  id: string;
  measured_on: string;
  measured_at: string | null;
  score: number;
  weight_kg: number;
  bmi: number;
  body_fat_percent: number;
  body_age: number;
  body_type: string | null;
  muscle_kg: number;
  skeletal_muscle_kg: number;
  bone_mass_kg: number;
  water_percent: number;
  visceral_fat: number;
  bmr_kcal: number;
  protein_percent: number;
  trunk_fat_percent: number;
  trunk_muscle_kg: number;
  left_arm_fat_percent: number;
  left_arm_muscle_kg: number;
  right_arm_fat_percent: number;
  right_arm_muscle_kg: number;
  left_leg_fat_percent: number;
  left_leg_muscle_kg: number;
  right_leg_fat_percent: number;
  right_leg_muscle_kg: number;
  note: string | null;
  created_at: string;
};

type DailyActivityRow = {
  id: string;
  activity_on: string;
  source: string | null;
  steps: number;
  active_calories: number;
  total_calories: number;
  exercise_minutes: number;
  stand_hours: number;
  distance_km: number;
  floors: number;
  resting_heart_rate: number;
  hrv_ms: number;
  sleep_minutes: number;
  raw_metrics: Record<string, { label: string; category: string; value: number; unit: string }> | null;
  note: string | null;
  created_at: string;
};

type ExerciseActivityRow = {
  id: string;
  activity_on: string;
  started_at: string | null;
  source: string | null;
  external_id: string | null;
  type: string | null;
  title: string | null;
  duration_minutes: number;
  distance_km: number;
  active_calories: number;
  avg_heart_rate: number;
  max_heart_rate: number;
  elevation_gain_m: number;
  note: string | null;
  created_at: string;
};

type ImportPhoto = {
  key: string;
  date: string;
  fileName: string;
  contentType: string;
  dataUrl: string;
};

type ImportItem = {
  sourceId: string;
  date: string;
  meal: MealType;
  name: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  note: string;
  photoKeys: string[];
  createdAt: string;
};

type ImportBundle = {
  photos: ImportPhoto[];
  items: ImportItem[];
};

export type ManualFoodInput = {
  date: string;
  meal: MealType;
  name: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  note: string;
  photos?: File[];
  retainedPhotoPaths?: string[];
};

export type BodyMetricInput = {
  date: string;
  measuredAt: string;
  score: number;
  weightKg: number;
  bmi: number;
  bodyFatPercent: number;
  bodyAge: number;
  bodyType: string;
  muscleKg: number;
  skeletalMuscleKg: number;
  boneMassKg: number;
  waterPercent: number;
  visceralFat: number;
  bmrKcal: number;
  proteinPercent: number;
  trunkFatPercent: number;
  trunkMuscleKg: number;
  leftArmFatPercent: number;
  leftArmMuscleKg: number;
  rightArmFatPercent: number;
  rightArmMuscleKg: number;
  leftLegFatPercent: number;
  leftLegMuscleKg: number;
  rightLegFatPercent: number;
  rightLegMuscleKg: number;
  note: string;
};

export type DailyActivityInput = {
  date: string;
  source: string;
  steps: number;
  activeCalories: number;
  totalCalories: number;
  exerciseMinutes: number;
  standHours: number;
  distanceKm: number;
  floors: number;
  restingHeartRate: number;
  hrvMs: number;
  sleepMinutes: number;
  rawMetrics?: Record<string, { label: string; category: string; value: number; unit: string }>;
  note: string;
};

export type ExerciseActivityInput = {
  date: string;
  startedAt: string;
  source: string;
  externalId?: string;
  type: string;
  title: string;
  durationMinutes: number;
  distanceKm: number;
  activeCalories: number;
  avgHeartRate: number;
  maxHeartRate: number;
  elevationGainM: number;
  note: string;
};

function rowToFoodItemBase(row: MealRow, photoUrls: string[]): FoodItem {
  return {
    id: row.id,
    date: row.eaten_on,
    meal: row.meal,
    name: row.name,
    grams: Number(row.grams || 0),
    calories: Number(row.calories || 0),
    protein: Number(row.protein || 0),
    carbs: Number(row.carbs || 0),
    fat: Number(row.fat || 0),
    fiber: Number(row.fiber || 0),
    note: row.note || "",
    photoUrls,
    photoPaths: row.photo_urls || [],
    createdAt: row.created_at,
  };
}

async function rowToFoodItem(row: MealRow): Promise<FoodItem> {
  const photoUrls = await resolvePhotoUrls(row.photo_urls || []);
  return rowToFoodItemBase(row, photoUrls);
}

async function rowsToFoodItems(rows: MealRow[]): Promise<FoodItem[]> {
  const allPaths = [...new Set(rows.flatMap((row) => row.photo_urls || []))];
  const resolvedUrls = await resolvePhotoUrls(allPaths);
  const urlMap = new Map(allPaths.map((path, index) => [path, resolvedUrls[index]]));
  return rows.map((row) => rowToFoodItemBase(row, (row.photo_urls || []).map((path) => urlMap.get(path) || path)));
}

function rowToBodyMetric(row: BodyMetricRow): BodyMetric {
  return {
    id: row.id,
    date: row.measured_on,
    measuredAt: row.measured_at || "",
    score: Number(row.score || 0),
    weightKg: Number(row.weight_kg || 0),
    bmi: Number(row.bmi || 0),
    bodyFatPercent: Number(row.body_fat_percent || 0),
    bodyAge: Number(row.body_age || 0),
    bodyType: row.body_type || "",
    muscleKg: Number(row.muscle_kg || 0),
    skeletalMuscleKg: Number(row.skeletal_muscle_kg || 0),
    boneMassKg: Number(row.bone_mass_kg || 0),
    waterPercent: Number(row.water_percent || 0),
    visceralFat: Number(row.visceral_fat || 0),
    bmrKcal: Number(row.bmr_kcal || 0),
    proteinPercent: Number(row.protein_percent || 0),
    trunkFatPercent: Number(row.trunk_fat_percent || 0),
    trunkMuscleKg: Number(row.trunk_muscle_kg || 0),
    leftArmFatPercent: Number(row.left_arm_fat_percent || 0),
    leftArmMuscleKg: Number(row.left_arm_muscle_kg || 0),
    rightArmFatPercent: Number(row.right_arm_fat_percent || 0),
    rightArmMuscleKg: Number(row.right_arm_muscle_kg || 0),
    leftLegFatPercent: Number(row.left_leg_fat_percent || 0),
    leftLegMuscleKg: Number(row.left_leg_muscle_kg || 0),
    rightLegFatPercent: Number(row.right_leg_fat_percent || 0),
    rightLegMuscleKg: Number(row.right_leg_muscle_kg || 0),
    note: row.note || "",
    createdAt: row.created_at,
  };
}

function rowToDailyActivity(row: DailyActivityRow): DailyActivity {
  return {
    id: row.id,
    date: row.activity_on,
    source: row.source || "manual",
    steps: Number(row.steps || 0),
    activeCalories: Number(row.active_calories || 0),
    totalCalories: Number(row.total_calories || 0),
    exerciseMinutes: Number(row.exercise_minutes || 0),
    standHours: Number(row.stand_hours || 0),
    distanceKm: Number(row.distance_km || 0),
    floors: Number(row.floors || 0),
    restingHeartRate: Number(row.resting_heart_rate || 0),
    hrvMs: Number(row.hrv_ms || 0),
    sleepMinutes: Number(row.sleep_minutes || 0),
    rawMetrics: row.raw_metrics || {},
    note: row.note || "",
    createdAt: row.created_at,
  };
}

function rowToExerciseActivity(row: ExerciseActivityRow): ExerciseActivity {
  return {
    id: row.id,
    date: row.activity_on,
    startedAt: row.started_at || "",
    source: row.source || "manual",
    externalId: row.external_id || "",
    type: row.type || "其他",
    title: row.title || row.type || "运动",
    durationMinutes: Number(row.duration_minutes || 0),
    distanceKm: Number(row.distance_km || 0),
    activeCalories: Number(row.active_calories || 0),
    avgHeartRate: Number(row.avg_heart_rate || 0),
    maxHeartRate: Number(row.max_heart_rate || 0),
    elevationGainM: Number(row.elevation_gain_m || 0),
    note: row.note || "",
    createdAt: row.created_at,
  };
}

const PHOTO_SIGNED_URL_TTL_SECONDS = 60 * 60 * 24;

async function resolvePhotoUrls(photoPaths: string[]): Promise<string[]> {
  if (!photoPaths.length || !supabase) return photoPaths;
  const toSign = photoPaths.filter((path) => path && !path.startsWith("http") && !path.startsWith("/"));
  if (!toSign.length) return photoPaths;
  const { data, error } = await supabase.storage.from(configuredStorageBucket).createSignedUrls(toSign, PHOTO_SIGNED_URL_TTL_SECONDS);
  if (error) throw error;
  const signedMap = new Map(toSign.map((path, index) => [path, data[index]?.signedUrl || ""]));
  return photoPaths.map((path) => (!path || path.startsWith("http") || path.startsWith("/")) ? path : (signedMap.get(path) || ""));
}

export async function getCurrentUser() {
  if (!supabase) return null;
  const { data } = await supabase.auth.getUser();
  return data.user;
}

export function onAuthChange(callback: (user: { email?: string | null } | null) => void) {
  if (!supabase) return () => undefined;
  const { data } = supabase.auth.onAuthStateChange((_event, session) => callback(session?.user ?? null));
  return () => data.subscription.unsubscribe();
}

export async function signInWithEmail(email: string) {
  if (!supabase) return;
  const redirectTo = window.location.origin;
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: redirectTo },
  });
  if (error) throw error;
}

export async function signOut() {
  if (!supabase) return;
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function fetchFoodItems(): Promise<FoodItem[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from("food_items")
    .select("*")
    .order("eaten_on", { ascending: false })
    .order("created_at", { ascending: true });

  if (error) throw error;
  return rowsToFoodItems(data as MealRow[]);
}

export async function fetchBodyMetrics(): Promise<BodyMetric[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from("body_metrics")
    .select("*")
    .order("measured_on", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data as BodyMetricRow[]).map(rowToBodyMetric);
}

export async function fetchDailyActivities(): Promise<DailyActivity[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from("daily_activities")
    .select("*")
    .order("activity_on", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data as DailyActivityRow[]).map(rowToDailyActivity);
}

export async function fetchExerciseActivities(): Promise<ExerciseActivity[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from("exercise_activities")
    .select("*")
    .order("activity_on", { ascending: false })
    .order("started_at", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data as ExerciseActivityRow[]).map(rowToExerciseActivity);
}

function safeStorageName(fileName: string) {
  return fileName.replace(/[^a-zA-Z0-9._-]/g, "-");
}

async function uploadPhotoFiles(userId: string, date: string, photos: File[] = []) {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const photoPaths: string[] = [];
  const compressedPhotos = await compressPhotosForUpload(photos);
  for (const file of compressedPhotos) {
    const storagePath = `${userId}/${date}/${Date.now()}-${safeStorageName(file.name)}`;
    const { error } = await supabase.storage
      .from(configuredStorageBucket)
      .upload(storagePath, file, {
        contentType: file.type || "application/octet-stream",
        upsert: false,
      });
    if (error) throw error;
    photoPaths.push(storagePath);
  }
  return photoPaths;
}

async function removeUnreferencedPhotoPaths(userId: string, paths: string[]) {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const removable: string[] = [];
  for (const path of paths.filter((item) => item.startsWith(`${userId}/`))) {
    const { data, error } = await supabase
      .from("food_items")
      .select("id")
      .contains("photo_urls", [path])
      .limit(1);
    if (error) throw error;
    if (!data?.length) removable.push(path);
  }
  if (removable.length) {
    await supabase.storage.from(configuredStorageBucket).remove(removable);
  }
}

function blobFromDataUrl(dataUrl: string) {
  const [header, base64] = dataUrl.split(",");
  if (!header || !base64) throw new Error("导入包里的照片格式不正确。");
  const contentType = header.match(/data:(.*?);base64/)?.[1] || "application/octet-stream";
  const bytes = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
  return new Blob([bytes], { type: contentType });
}

export async function importDiaryBundle(bundle: ImportBundle) {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  if (!bundle?.items?.length) throw new Error("导入包里没有饮食记录。");

  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再导入。");

  const uploadedPhotos = new Map<string, string>();
  for (const photo of bundle.photos || []) {
    const storagePath = `${user.id}/${photo.date}/${safeStorageName(photo.fileName)}`;
    const { error } = await supabase.storage
      .from(configuredStorageBucket)
      .upload(storagePath, blobFromDataUrl(photo.dataUrl), {
        contentType: photo.contentType || "application/octet-stream",
        upsert: true,
      });
    if (error) throw error;
    uploadedPhotos.set(photo.key, storagePath);
  }

  let inserted = 0;
  let updated = 0;

  for (const item of bundle.items) {
    const row = {
      source_id: item.sourceId,
      eaten_on: item.date,
      meal: item.meal,
      name: item.name,
      grams: item.grams || 0,
      calories: item.calories || 0,
      protein: item.protein || 0,
      carbs: item.carbs || 0,
      fat: item.fat || 0,
      fiber: item.fiber || 0,
      note: item.note || null,
      photo_urls: item.photoKeys.map((key) => uploadedPhotos.get(key)).filter(Boolean),
      created_at: item.createdAt,
    };

    const { data: existing, error: selectError } = await supabase
      .from("food_items")
      .select("id")
      .eq("source_id", item.sourceId)
      .maybeSingle();
    if (selectError) throw selectError;

    if (existing?.id) {
      const { error } = await supabase.from("food_items").update(row).eq("id", existing.id);
      if (error) throw error;
      updated += 1;
    } else {
      const { error } = await supabase.from("food_items").insert(row);
      if (error) throw error;
      inserted += 1;
    }
  }

  return { inserted, updated, photosUploaded: uploadedPhotos.size };
}

export async function createFoodItem(input: ManualFoodInput): Promise<FoodItem> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再新增记录。");

  const photoPaths = await uploadPhotoFiles(user.id, input.date, input.photos || []);

  const row = {
    source_id: `manual-${crypto.randomUUID()}`,
    eaten_on: input.date,
    meal: input.meal,
    name: input.name.trim(),
    grams: input.grams || 0,
    calories: input.calories || 0,
    protein: input.protein || 0,
    carbs: input.carbs || 0,
    fat: input.fat || 0,
    fiber: input.fiber || 0,
    note: input.note.trim() || null,
    photo_urls: photoPaths,
  };

  const { data, error } = await supabase.from("food_items").insert(row).select("*").single();
  if (error) throw error;

  return rowToFoodItem(data as MealRow);
}

export async function createFoodItems(inputs: ManualFoodInput[], sharedPhotos: File[] = []): Promise<FoodItem[]> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再新增记录。");
  if (!inputs.length) throw new Error("没有可保存的食物。");

  const firstDate = inputs[0].date;
  const sharedPhotoPaths = await uploadPhotoFiles(user.id, firstDate, sharedPhotos);
  const rows = inputs.map((input) => ({
    source_id: `manual-${crypto.randomUUID()}`,
    eaten_on: input.date,
    meal: input.meal,
    name: input.name.trim(),
    grams: input.grams || 0,
    calories: input.calories || 0,
    protein: input.protein || 0,
    carbs: input.carbs || 0,
    fat: input.fat || 0,
    fiber: input.fiber || 0,
    note: input.note.trim() || null,
    photo_urls: sharedPhotoPaths,
  }));

  const { data, error } = await supabase.from("food_items").insert(rows).select("*");
  if (error) throw error;

  return rowsToFoodItems(data as MealRow[]);
}

export async function updateFoodItem(id: string, input: ManualFoodInput): Promise<FoodItem> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再修改记录。");

  const { data: existing, error: selectError } = await supabase
    .from("food_items")
    .select("photo_urls")
    .eq("id", id)
    .single();
  if (selectError) throw selectError;

  const newPhotoPaths = await uploadPhotoFiles(user.id, input.date, input.photos || []);

  const row = {
    eaten_on: input.date,
    meal: input.meal,
    name: input.name.trim(),
    grams: input.grams || 0,
    calories: input.calories || 0,
    protein: input.protein || 0,
    carbs: input.carbs || 0,
    fat: input.fat || 0,
    fiber: input.fiber || 0,
    note: input.note.trim() || null,
    photo_urls: [...(input.retainedPhotoPaths ?? (((existing as { photo_urls?: string[] | null })?.photo_urls) || [])), ...newPhotoPaths],
  };

  const previousPhotoPaths = (((existing as { photo_urls?: string[] | null })?.photo_urls) || []);
  const { data, error } = await supabase.from("food_items").update(row).eq("id", id).select("*").single();
  if (error) throw error;

  const removedPhotoPaths = previousPhotoPaths.filter((path) => !row.photo_urls.includes(path));
  if (removedPhotoPaths.length) await removeUnreferencedPhotoPaths(user.id, removedPhotoPaths);

  return rowToFoodItem(data as MealRow);
}

export async function deleteFoodItem(item: FoodItem): Promise<void> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再删除记录。");

  const { error } = await supabase.from("food_items").delete().eq("id", item.id);
  if (error) throw error;

  if (item.photoPaths.length) await removeUnreferencedPhotoPaths(user.id, item.photoPaths);
}

function toMeasuredAt(value: string, date: string) {
  if (!value) return `${date}T00:00:00`;
  return value.length === 16 ? `${value}:00` : value;
}

export async function upsertBodyMetric(input: BodyMetricInput): Promise<BodyMetric> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再记录身体数据。");

  const row = {
    user_id: user.id,
    measured_on: input.date,
    measured_at: toMeasuredAt(input.measuredAt, input.date),
    score: input.score || 0,
    weight_kg: input.weightKg || 0,
    bmi: input.bmi || 0,
    body_fat_percent: input.bodyFatPercent || 0,
    body_age: input.bodyAge || 0,
    body_type: input.bodyType.trim() || null,
    muscle_kg: input.muscleKg || 0,
    skeletal_muscle_kg: input.skeletalMuscleKg || 0,
    bone_mass_kg: input.boneMassKg || 0,
    water_percent: input.waterPercent || 0,
    visceral_fat: input.visceralFat || 0,
    bmr_kcal: input.bmrKcal || 0,
    protein_percent: input.proteinPercent || 0,
    trunk_fat_percent: input.trunkFatPercent || 0,
    trunk_muscle_kg: input.trunkMuscleKg || 0,
    left_arm_fat_percent: input.leftArmFatPercent || 0,
    left_arm_muscle_kg: input.leftArmMuscleKg || 0,
    right_arm_fat_percent: input.rightArmFatPercent || 0,
    right_arm_muscle_kg: input.rightArmMuscleKg || 0,
    left_leg_fat_percent: input.leftLegFatPercent || 0,
    left_leg_muscle_kg: input.leftLegMuscleKg || 0,
    right_leg_fat_percent: input.rightLegFatPercent || 0,
    right_leg_muscle_kg: input.rightLegMuscleKg || 0,
    note: input.note.trim() || null,
  };

  const { data, error } = await supabase
    .from("body_metrics")
    .upsert(row, { onConflict: "user_id,measured_on" })
    .select("*")
    .single();

  if (error) throw error;
  return rowToBodyMetric(data as BodyMetricRow);
}

export async function deleteBodyMetric(id: string): Promise<void> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const { error } = await supabase.from("body_metrics").delete().eq("id", id);
  if (error) throw error;
}

export async function upsertDailyActivity(input: DailyActivityInput): Promise<DailyActivity> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再记录运动数据。");

  const row = {
    user_id: user.id,
    activity_on: input.date,
    source: input.source || "manual",
    steps: input.steps || 0,
    active_calories: input.activeCalories || 0,
    total_calories: input.totalCalories || 0,
    exercise_minutes: input.exerciseMinutes || 0,
    stand_hours: input.standHours || 0,
    distance_km: input.distanceKm || 0,
    floors: input.floors || 0,
    resting_heart_rate: input.restingHeartRate || 0,
    hrv_ms: input.hrvMs || 0,
    sleep_minutes: input.sleepMinutes || 0,
    raw_metrics: input.rawMetrics || {},
    note: input.note.trim() || null,
  };

  const { data, error } = await supabase
    .from("daily_activities")
    .upsert(row, { onConflict: "user_id,activity_on,source" })
    .select("*")
    .single();

  if (error) throw error;
  return rowToDailyActivity(data as DailyActivityRow);
}

export async function deleteDailyActivity(id: string): Promise<void> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const { error } = await supabase.from("daily_activities").delete().eq("id", id);
  if (error) throw error;
}

export async function createExerciseActivity(input: ExerciseActivityInput): Promise<ExerciseActivity> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再记录训练。");

  const row = {
    user_id: user.id,
    activity_on: input.date,
    started_at: toMeasuredAt(input.startedAt, input.date),
    source: input.source || "manual",
    external_id: input.externalId || null,
    type: input.type.trim() || "其他",
    title: input.title.trim() || input.type.trim() || "运动",
    duration_minutes: input.durationMinutes || 0,
    distance_km: input.distanceKm || 0,
    active_calories: input.activeCalories || 0,
    avg_heart_rate: input.avgHeartRate || 0,
    max_heart_rate: input.maxHeartRate || 0,
    elevation_gain_m: input.elevationGainM || 0,
    note: input.note.trim() || null,
  };

  const { data, error } = await supabase.from("exercise_activities").insert(row).select("*").single();
  if (error) throw error;
  return rowToExerciseActivity(data as ExerciseActivityRow);
}

export async function updateExerciseActivity(id: string, input: ExerciseActivityInput): Promise<ExerciseActivity> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再修改训练。");

  const row = {
    activity_on: input.date,
    started_at: toMeasuredAt(input.startedAt, input.date),
    source: input.source || "manual",
    external_id: input.externalId || null,
    type: input.type.trim() || "其他",
    title: input.title.trim() || input.type.trim() || "运动",
    duration_minutes: input.durationMinutes || 0,
    distance_km: input.distanceKm || 0,
    active_calories: input.activeCalories || 0,
    avg_heart_rate: input.avgHeartRate || 0,
    max_heart_rate: input.maxHeartRate || 0,
    elevation_gain_m: input.elevationGainM || 0,
    note: input.note.trim() || null,
  };

  const { data, error } = await supabase.from("exercise_activities").update(row).eq("id", id).select("*").single();
  if (error) throw error;
  return rowToExerciseActivity(data as ExerciseActivityRow);
}

export async function deleteExerciseActivity(id: string): Promise<void> {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const { error } = await supabase.from("exercise_activities").delete().eq("id", id);
  if (error) throw error;
}

export type ExerciseImportProgress = {
  phase: "daily" | "workouts";
  imported: number;
  total: number;
};

export async function importExerciseData(
  dailyInputs: DailyActivityInput[],
  workoutInputs: ExerciseActivityInput[],
  onProgress?: (progress: ExerciseImportProgress) => void,
) {
  if (!supabase) throw new Error("Supabase 还没有配置。");
  const user = await getCurrentUser();
  if (!user) throw new Error("请先登录后再导入运动数据。");

  let dailyImported = 0;
  let workoutsImported = 0;
  const appleHealthDates = [...dailyInputs, ...workoutInputs]
    .filter((input) => input.source === "apple_health")
    .map((input) => input.date)
    .filter(Boolean)
    .sort();

  if (appleHealthDates.length) {
    const firstDate = appleHealthDates[0];
    const lastDate = appleHealthDates[appleHealthDates.length - 1];
    const { error: dailyDeleteError } = await supabase
      .from("daily_activities")
      .delete()
      .eq("user_id", user.id)
      .eq("source", "apple_health")
      .gte("activity_on", firstDate)
      .lte("activity_on", lastDate);
    if (dailyDeleteError) throw dailyDeleteError;

    const { error: workoutDeleteError } = await supabase
      .from("exercise_activities")
      .delete()
      .eq("user_id", user.id)
      .eq("source", "apple_health")
      .gte("activity_on", firstDate)
      .lte("activity_on", lastDate);
    if (workoutDeleteError) throw workoutDeleteError;
  }

  for (const chunk of chunkArray(dailyInputs, 50)) {
    const rows = chunk.map((input) => ({
      user_id: user.id,
      activity_on: input.date,
      source: input.source || "import",
      steps: input.steps || 0,
      active_calories: input.activeCalories || 0,
      total_calories: input.totalCalories || 0,
      exercise_minutes: input.exerciseMinutes || 0,
      stand_hours: input.standHours || 0,
      distance_km: input.distanceKm || 0,
      floors: input.floors || 0,
      resting_heart_rate: input.restingHeartRate || 0,
      hrv_ms: input.hrvMs || 0,
      sleep_minutes: input.sleepMinutes || 0,
      raw_metrics: input.rawMetrics || {},
      note: input.note.trim() || null,
    }));
    const { error } = await supabase.from("daily_activities").upsert(rows, { onConflict: "user_id,activity_on,source" });
    if (error) throw error;
    dailyImported += rows.length;
    onProgress?.({ phase: "daily", imported: dailyImported, total: dailyInputs.length });
  }

  for (const chunk of chunkArray(workoutInputs, 100)) {
    const rows = chunk.map((input) => ({
      user_id: user.id,
      activity_on: input.date,
      started_at: toMeasuredAt(input.startedAt, input.date),
      source: input.source || "import",
      external_id: input.externalId || `import-${crypto.randomUUID()}`,
      type: input.type.trim() || "其他",
      title: input.title.trim() || input.type.trim() || "运动",
      duration_minutes: input.durationMinutes || 0,
      distance_km: input.distanceKm || 0,
      active_calories: input.activeCalories || 0,
      avg_heart_rate: input.avgHeartRate || 0,
      max_heart_rate: input.maxHeartRate || 0,
      elevation_gain_m: input.elevationGainM || 0,
      note: input.note.trim() || null,
    }));
    const { error } = await supabase.from("exercise_activities").upsert(rows, { onConflict: "user_id,source,external_id" });
    if (error) throw error;
    workoutsImported += rows.length;
    onProgress?.({ phase: "workouts", imported: workoutsImported, total: workoutInputs.length });
  }

  return { dailyImported, workoutsImported };
}

function chunkArray<T>(items: T[], size: number) {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}
