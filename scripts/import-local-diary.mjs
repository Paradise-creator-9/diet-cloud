import { createClient } from "@supabase/supabase-js";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";

const root = path.resolve(import.meta.dirname, "..");
const localDiaryRoot = path.resolve(root, "..", "diet-diary");
const dataFile = process.env.LOCAL_DIARY_DATA || path.join(localDiaryRoot, "data", "assistant-data.js");
const bucket = process.env.SUPABASE_STORAGE_BUCKET || "meal-photos";

const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const userId = process.env.DIARY_USER_ID;

if (!supabaseUrl || !serviceRoleKey || !userId) {
  console.error("Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or DIARY_USER_ID.");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

function normalizePhotoList(item) {
  const raw = item.images || item.photoUrls || (item.image ? [item.image] : []);
  return raw.filter(Boolean);
}

function storagePathFor(date, photo) {
  const cleanName = path.basename(photo).replace(/[^a-zA-Z0-9._-]/g, "-");
  return `${userId}/${date}/${cleanName}`;
}

async function uploadPhoto(date, photo) {
  const localPath = path.resolve(localDiaryRoot, photo.replace(/^\.\//, ""));
  const storagePath = storagePathFor(date, photo);
  const body = await fs.readFile(localPath);
  const ext = path.extname(localPath).toLowerCase();
  const contentType =
    ext === ".png" ? "image/png" :
    ext === ".webp" ? "image/webp" :
    ext === ".heic" || ext === ".heif" ? "image/heic" :
    "image/jpeg";

  const { error } = await supabase.storage
    .from(bucket)
    .upload(storagePath, body, { contentType, upsert: true });

  if (error) throw error;
  return storagePath;
}

async function loadLocalData() {
  const source = await fs.readFile(dataFile, "utf8");
  const context = { window: {} };
  vm.runInNewContext(source, context, { filename: dataFile });
  return context.window.DIET_DIARY_ASSISTANT_DATA || {};
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
    const { error } = await supabase
      .from("food_items")
      .update(row)
      .eq("id", existing.id);
    if (error) throw error;
    return "updated";
  }

  const { error } = await supabase.from("food_items").insert(row);
  if (error) throw error;
  return "inserted";
}

const localData = await loadLocalData();
const photoCache = new Map();
let inserted = 0;
let updated = 0;

for (const [date, day] of Object.entries(localData)) {
  for (const [meal, items] of Object.entries(day.meals || {})) {
    for (const item of items) {
      const photoUrls = [];
      for (const photo of normalizePhotoList(item)) {
        const cacheKey = `${date}:${photo}`;
        if (!photoCache.has(cacheKey)) {
          photoCache.set(cacheKey, await uploadPhoto(date, photo));
        }
        photoUrls.push(photoCache.get(cacheKey));
      }

      const result = await upsertFoodItem({
        user_id: userId,
        source_id: item.id,
        eaten_on: date,
        meal,
        name: item.name,
        grams: item.grams || 0,
        calories: item.calories || 0,
        protein: item.protein || 0,
        carbs: item.carbs || 0,
        fat: item.fat || 0,
        fiber: item.fiber || 0,
        note: item.note || null,
        photo_urls: photoUrls,
        created_at: item.createdAt || day.createdAt || new Date().toISOString(),
      });

      if (result === "updated") updated += 1;
      else inserted += 1;
    }
  }
}

console.log(`Imported local diary: ${inserted} inserted, ${updated} updated, ${photoCache.size} photos uploaded.`);
