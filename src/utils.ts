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
