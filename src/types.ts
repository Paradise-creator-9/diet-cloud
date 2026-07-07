export type MealType = "breakfast" | "lunch" | "dinner" | "snack";

export type FoodItem = {
  id: string;
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
  photoUrls: string[];
  photoPaths: string[];
  createdAt: string;
};

export type BodyMetric = {
  id: string;
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
  createdAt: string;
};

export type DailyActivity = {
  id: string;
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
  rawMetrics: Record<string, HealthMetricValue>;
  note: string;
  createdAt: string;
};

export type HealthMetricValue = {
  label: string;
  category: string;
  value: number;
  unit: string;
};

export type ExerciseActivity = {
  id: string;
  date: string;
  startedAt: string;
  source: string;
  externalId: string;
  type: string;
  title: string;
  durationMinutes: number;
  distanceKm: number;
  activeCalories: number;
  avgHeartRate: number;
  maxHeartRate: number;
  elevationGainM: number;
  note: string;
  createdAt: string;
};

export type DailyTotals = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  grams: number;
};

export type MealMeta = {
  key: MealType;
  title: string;
  hint: string;
};
