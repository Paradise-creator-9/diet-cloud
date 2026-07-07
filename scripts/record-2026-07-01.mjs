import { createClient } from "@supabase/supabase-js";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const envPath = path.join(root, ".env.runtime");
const env = await loadEnv(envPath);

const supabaseUrl = process.env.SUPABASE_URL || env.SUPABASE_URL || env.VITE_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SERVICE_ROLE_KEY;
const userEmail = process.env.DIARY_USER_EMAIL || env.DIARY_USER_EMAIL;
const bucket = process.env.SUPABASE_STORAGE_BUCKET || env.SUPABASE_STORAGE_BUCKET || env.VITE_SUPABASE_STORAGE_BUCKET || "meal-photos";
const breakfastPhoto = process.env.DIARY_PHOTO_PATH || env.DIARY_PHOTO_PATH;

if (!supabaseUrl || !serviceRoleKey || !userEmail || !breakfastPhoto) {
  throw new Error("Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DIARY_USER_EMAIL, or DIARY_PHOTO_PATH.");
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

const userId = await getUserId(userEmail);
const date = "2026-07-01";
const photoPath = await uploadPhoto(userId, date, breakfastPhoto);

const bodyMetric = {
  user_id: userId,
  measured_on: date,
  measured_at: "2026-07-01T08:27:36+09:00",
  score: 65,
  weight_kg: 75.0,
  bmi: 24.2,
  body_fat_percent: 20.9,
  body_age: 29,
  body_type: "肥胖",
  muscle_kg: 56.5,
  skeletal_muscle_kg: 56.5,
  bone_mass_kg: 2.9,
  water_percent: 55.0,
  visceral_fat: 8.5,
  bmr_kcal: 1697,
  protein_percent: 20.3,
  trunk_fat_percent: 22.56,
  trunk_muscle_kg: 28.92,
  left_arm_fat_percent: 15.84,
  left_arm_muscle_kg: 2.73,
  right_arm_fat_percent: 14.74,
  right_arm_muscle_kg: 2.95,
  left_leg_fat_percent: 19.66,
  left_leg_muscle_kg: 10.4,
  right_leg_fat_percent: 19.49,
  right_leg_muscle_kg: 10.53,
  note: "来自 2026/07/01 08:27:36 体脂秤截图。",
};

const breakfastItems = [
  {
    source_id: "chat-2026-07-01-breakfast-raw-oats-60g",
    name: "生燕麦",
    grams: 60,
    calories: 233,
    protein: 10.1,
    carbs: 39.8,
    fat: 4.1,
    fiber: 6.4,
    note: "按 60g 生燕麦估算。",
  },
  {
    source_id: "chat-2026-07-01-breakfast-milk-200g",
    name: "牛奶",
    grams: 200,
    calories: 124,
    protein: 6.6,
    carbs: 9.6,
    fat: 6.6,
    fiber: 0,
    note: "按 200g 普通牛奶估算。",
  },
  {
    source_id: "chat-2026-07-01-breakfast-espresso",
    name: "浓缩咖啡",
    grams: 45,
    calories: 5,
    protein: 0.2,
    carbs: 0.8,
    fat: 0,
    fiber: 0,
    note: "无糖浓缩咖啡估算。",
  },
];

for (const item of breakfastItems) {
  await upsertFoodItem({
    user_id: userId,
    eaten_on: date,
    meal: "breakfast",
    photo_urls: [photoPath],
    created_at: "2026-07-01T09:28:00+09:00",
    ...item,
  });
}

let bodyStatus = "skipped";
try {
  await upsertBodyMetric(bodyMetric);
  bodyStatus = "upserted";
} catch (error) {
  bodyStatus = `failed: ${error.message || String(error)}`;
}

console.log(`Recorded ${date}: ${breakfastItems.length} breakfast items upserted, 1 photo uploaded, body metrics ${bodyStatus}.`);

async function loadEnv(filePath) {
  try {
    return parseEnv(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error && error.code === "ENOENT") return {};
    throw error;
  }
}

function parseEnv(source) {
  const result = {};
  for (const line of source.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const index = trimmed.indexOf("=");
    if (index === -1) continue;
    const key = trimmed.slice(0, index);
    let value = trimmed.slice(index + 1);
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    result[key] = value;
  }
  return result;
}

async function getUserId(email) {
  const { data, error } = await supabase.auth.admin.listUsers();
  if (error) throw error;
  const user = data.users.find((item) => item.email?.toLowerCase() === email.toLowerCase());
  if (!user) throw new Error(`No Supabase user found for ${email}.`);
  return user.id;
}

async function uploadPhoto(userId, date, localPath) {
  const file = await fs.readFile(localPath);
  const cleanName = path.basename(localPath).replace(/[^a-zA-Z0-9._-]/g, "-");
  const storagePath = `${userId}/${date}/breakfast-${cleanName}`;
  const { error } = await supabase.storage
    .from(bucket)
    .upload(storagePath, file, { contentType: "image/jpeg", upsert: true });
  if (error) throw error;
  return storagePath;
}

async function upsertFoodItem(row) {
  const { data: existing, error: selectError } = await supabase
    .from("food_items")
    .select("id")
    .eq("user_id", row.user_id)
    .eq("source_id", row.source_id)
    .maybeSingle();
  if (selectError) throw selectError;

  if (existing?.id) {
    const { error } = await supabase.from("food_items").update(row).eq("id", existing.id);
    if (error) throw error;
    return;
  }

  const { error } = await supabase.from("food_items").insert(row);
  if (error) throw error;
}

async function upsertBodyMetric(row) {
  const { error } = await supabase
    .from("body_metrics")
    .upsert(row, { onConflict: "user_id,measured_on" });
  if (error) throw error;
}
