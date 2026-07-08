import type { DailyTotals, FoodItem, MealType } from "./types";

export function formatDateLabel(dateKey: string) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    weekday: "long",
  }).format(new Date(year, month - 1, day));
}

export function totalsFor(items: FoodItem[]): DailyTotals {
  return items.reduce(
    (sum, item) => {
      sum.calories += item.calories;
      sum.protein += item.protein;
      sum.carbs += item.carbs;
      sum.fat += item.fat;
      sum.fiber += item.fiber;
      sum.grams += item.grams;
      return sum;
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, grams: 0 },
  );
}

export function round(value: number) {
  return Math.round(value);
}

export function itemsByMeal(items: FoodItem[], meal: MealType) {
  return items.filter((item) => item.meal === meal);
}

export function uniquePhotos(items: FoodItem[]) {
  return [...new Set(items.flatMap((item) => item.photoUrls).filter(Boolean))];
}

export function buildDates(items: FoodItem[]) {
  return [...new Set(items.map((item) => item.date))].sort((a, b) => b.localeCompare(a));
}

const PHOTO_COMPRESS_MAX_BYTES = 300 * 1024;

/** 上传前压缩照片:目标 150-300KB,超出上限时逐步降质量/降尺寸直到达标。 */
export async function compressPhotoForUpload(file: File): Promise<File> {
  if (!file.type.startsWith("image/") || file.size <= PHOTO_COMPRESS_MAX_BYTES) return file;

  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    bitmap.close();
    return file;
  }

  let width = bitmap.width;
  let height = bitmap.height;
  let quality = 0.9;
  let best: Blob | null = null;

  for (let attempt = 0; attempt < 10; attempt++) {
    canvas.width = width;
    canvas.height = height;
    ctx.clearRect(0, 0, width, height);
    ctx.drawImage(bitmap, 0, 0, width, height);
    const blob: Blob | null = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
    if (!blob) break;
    best = blob;
    if (blob.size <= PHOTO_COMPRESS_MAX_BYTES) break;
    if (quality > 0.4) {
      quality -= 0.1;
    } else {
      width = Math.round(width * 0.85);
      height = Math.round(height * 0.85);
    }
  }

  bitmap.close();
  if (!best || best.size >= file.size) return file;

  const compressedName = file.name.replace(/\.\w+$/, "") + ".jpg";
  return new File([best], compressedName, { type: "image/jpeg", lastModified: Date.now() });
}

export async function compressPhotosForUpload(files: File[]): Promise<File[]> {
  return Promise.all(files.map((file) => compressPhotoForUpload(file)));
}
