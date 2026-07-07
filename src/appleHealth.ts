import { Unzip, UnzipInflate } from "fflate";
import type { DailyActivityInput, ExerciseActivityInput } from "./supabase";

export type HealthMetricDefinition = {
  type: string;
  label: string;
  category: string;
  unit: string;
  aggregation: "sum" | "avg" | "latest";
  converter?: "energy" | "distance" | "duration" | "mass" | "percent" | "temperature";
};

type DailyAccumulator = {
  date: string;
  steps: number;
  activeCalories: number;
  totalCalories: number;
  exerciseMinutes: number;
  standHours: number;
  distanceKm: number;
  floors: number;
  restingHeartRateValues: number[];
  hrvValues: number[];
  sleepMinutes: number;
  rawMetrics: Record<string, MetricAccumulator>;
  sourceMetrics: Record<string, Record<string, SourceMetricAccumulator>>;
};

type MetricAccumulator = HealthMetricDefinition & {
  sum: number;
  count: number;
  latest: number;
};

type SourceMetricAccumulator = MetricAccumulator & {
  sourceName: string;
  sourcePriority: number;
};

export type AppleHealthImportResult = {
  dailyActivities: DailyActivityInput[];
  workouts: ExerciseActivityInput[];
  summary: {
    dateCount: number;
    workoutCount: number;
    firstDate: string;
    lastDate: string;
    cutoffDate: string;
  };
};

export type AppleHealthParseProgress = {
  phase: "reading" | "parsing";
  bytesRead: number;
  totalBytes: number;
  recordsScanned: number;
  recordsKept: number;
  workoutsKept: number;
};

export const appleHealthMetricDefinitions: HealthMetricDefinition[] = [
  { type: "HKQuantityTypeIdentifierStepCount", label: "步数", category: "活动", unit: "步", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierActiveEnergyBurned", label: "活动能量", category: "活动", unit: "kcal", aggregation: "sum", converter: "energy" },
  { type: "HKQuantityTypeIdentifierBasalEnergyBurned", label: "静息能量", category: "活动", unit: "kcal", aggregation: "sum", converter: "energy" },
  { type: "HKQuantityTypeIdentifierAppleExerciseTime", label: "运动时间", category: "活动", unit: "分钟", aggregation: "sum", converter: "duration" },
  { type: "HKQuantityTypeIdentifierAppleStandTime", label: "站立时间", category: "活动", unit: "小时", aggregation: "sum", converter: "duration" },
  { type: "HKCategoryTypeIdentifierAppleStandHour", label: "站立小时", category: "活动", unit: "小时", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDistanceWalkingRunning", label: "步行+跑步距离", category: "活动", unit: "km", aggregation: "sum", converter: "distance" },
  { type: "HKQuantityTypeIdentifierDistanceCycling", label: "骑行距离", category: "活动", unit: "km", aggregation: "sum", converter: "distance" },
  { type: "HKQuantityTypeIdentifierFlightsClimbed", label: "爬楼", category: "活动", unit: "层", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierPushCount", label: "轮椅推动", category: "活动", unit: "次", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDistanceSwimming", label: "游泳距离", category: "活动", unit: "km", aggregation: "sum", converter: "distance" },
  { type: "HKQuantityTypeIdentifierSwimmingStrokeCount", label: "游泳划水", category: "活动", unit: "次", aggregation: "sum" },

  { type: "HKQuantityTypeIdentifierBodyMass", label: "体重", category: "身体测量", unit: "kg", aggregation: "latest", converter: "mass" },
  { type: "HKQuantityTypeIdentifierBodyMassIndex", label: "BMI", category: "身体测量", unit: "", aggregation: "latest" },
  { type: "HKQuantityTypeIdentifierBodyFatPercentage", label: "体脂率", category: "身体测量", unit: "%", aggregation: "latest", converter: "percent" },
  { type: "HKQuantityTypeIdentifierLeanBodyMass", label: "瘦体重", category: "身体测量", unit: "kg", aggregation: "latest", converter: "mass" },
  { type: "HKQuantityTypeIdentifierHeight", label: "身高", category: "身体测量", unit: "cm", aggregation: "latest" },
  { type: "HKQuantityTypeIdentifierWaistCircumference", label: "腰围", category: "身体测量", unit: "cm", aggregation: "latest" },

  { type: "HKQuantityTypeIdentifierHeartRate", label: "心率", category: "心脏", unit: "bpm", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierRestingHeartRate", label: "静息心率", category: "心脏", unit: "bpm", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierWalkingHeartRateAverage", label: "步行平均心率", category: "心脏", unit: "bpm", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", label: "HRV", category: "心脏", unit: "ms", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierVO2Max", label: "有氧适能 VO2 Max", category: "心脏", unit: "ml/kg/min", aggregation: "latest" },

  { type: "HKQuantityTypeIdentifierWalkingSpeed", label: "步行速度", category: "活动能力", unit: "km/h", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierWalkingStepLength", label: "步长", category: "活动能力", unit: "cm", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", label: "双脚支撑时间", category: "活动能力", unit: "%", aggregation: "avg", converter: "percent" },
  { type: "HKQuantityTypeIdentifierWalkingAsymmetryPercentage", label: "步行不对称", category: "活动能力", unit: "%", aggregation: "avg", converter: "percent" },
  { type: "HKQuantityTypeIdentifierStairAscentSpeed", label: "上楼速度", category: "活动能力", unit: "m/s", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierStairDescentSpeed", label: "下楼速度", category: "活动能力", unit: "m/s", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierSixMinuteWalkTestDistance", label: "六分钟步行距离", category: "活动能力", unit: "m", aggregation: "latest" },

  { type: "HKQuantityTypeIdentifierRespiratoryRate", label: "呼吸频率", category: "呼吸", unit: "次/分", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierOxygenSaturation", label: "血氧", category: "呼吸", unit: "%", aggregation: "avg", converter: "percent" },
  { type: "HKQuantityTypeIdentifierForcedVitalCapacity", label: "用力肺活量", category: "呼吸", unit: "L", aggregation: "latest" },
  { type: "HKQuantityTypeIdentifierPeakExpiratoryFlowRate", label: "峰值呼气流速", category: "呼吸", unit: "L/min", aggregation: "latest" },

  { type: "HKCategoryTypeIdentifierSleepAnalysis", label: "睡眠", category: "睡眠", unit: "分钟", aggregation: "sum" },

  { type: "HKQuantityTypeIdentifierBodyTemperature", label: "体温", category: "生命体征", unit: "°C", aggregation: "avg", converter: "temperature" },
  { type: "HKQuantityTypeIdentifierBloodPressureSystolic", label: "收缩压", category: "生命体征", unit: "mmHg", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierBloodPressureDiastolic", label: "舒张压", category: "生命体征", unit: "mmHg", aggregation: "avg" },
  { type: "HKQuantityTypeIdentifierBloodGlucose", label: "血糖", category: "生命体征", unit: "mg/dL", aggregation: "avg" },

  { type: "HKQuantityTypeIdentifierDietaryEnergyConsumed", label: "膳食能量", category: "营养", unit: "kcal", aggregation: "sum", converter: "energy" },
  { type: "HKQuantityTypeIdentifierDietaryWater", label: "水", category: "营养", unit: "mL", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDietaryProtein", label: "蛋白质", category: "营养", unit: "g", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDietaryCarbohydrates", label: "碳水化合物", category: "营养", unit: "g", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDietaryFatTotal", label: "总脂肪", category: "营养", unit: "g", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDietaryFiber", label: "膳食纤维", category: "营养", unit: "g", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDietarySugar", label: "糖", category: "营养", unit: "g", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDietarySodium", label: "钠", category: "营养", unit: "mg", aggregation: "sum" },
  { type: "HKQuantityTypeIdentifierDietaryCaffeine", label: "咖啡因", category: "营养", unit: "mg", aggregation: "sum" },
];

const metricDefinitionsByType = new Map(appleHealthMetricDefinitions.map((definition) => [definition.type, definition]));
const duplicateDailySourcePattern = /strava|garmin|connect|healthfit|zwift|wahoo|runkeeper|nike/i;
const duplicateWorkoutSourcePattern = /strava/i;
const preferredSourceMetricTypes = new Set([
  "HKQuantityTypeIdentifierStepCount",
  "HKQuantityTypeIdentifierActiveEnergyBurned",
  "HKQuantityTypeIdentifierBasalEnergyBurned",
  "HKQuantityTypeIdentifierAppleExerciseTime",
  "HKQuantityTypeIdentifierAppleStandTime",
  "HKCategoryTypeIdentifierAppleStandHour",
  "HKQuantityTypeIdentifierDistanceWalkingRunning",
  "HKQuantityTypeIdentifierFlightsClimbed",
  "HKQuantityTypeIdentifierRestingHeartRate",
  "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
]);

export async function parseAppleHealthExport(
  file: File,
  options: { cutoffDate?: string; onProgress?: (progress: AppleHealthParseProgress) => void } = {},
): Promise<AppleHealthImportResult> {
  const daily = new Map<string, DailyAccumulator>();
  const workouts: ExerciseActivityInput[] = [];
  const cutoffDate = options.cutoffDate || "";
  const decoder = new TextDecoder();
  let foundExportXml = false;
  let lineBuffer = "";
  const progress = {
    bytesRead: 0,
    totalBytes: file.size || 0,
    recordsScanned: 0,
    recordsKept: 0,
    workoutsKept: 0,
  };
  const emitProgress = (phase: AppleHealthParseProgress["phase"]) => {
    options.onProgress?.({
      phase,
      bytesRead: progress.bytesRead,
      totalBytes: progress.totalBytes,
      recordsScanned: progress.recordsScanned,
      recordsKept: progress.recordsKept,
      workoutsKept: progress.workoutsKept,
    });
  };

  await new Promise<void>((resolve, reject) => {
    const unzip = new Unzip((entry) => {
      if (!entry.name.endsWith("export.xml")) return;
      foundExportXml = true;
      entry.ondata = (error, data, final) => {
        if (error) {
          reject(error);
          return;
        }
        try {
          lineBuffer += decoder.decode(data, { stream: !final });
          lineBuffer = parseXmlLines(lineBuffer, daily, workouts, cutoffDate, final, progress);
          emitProgress("parsing");
          if (final) resolve();
        } catch (parseError) {
          reject(parseError);
        }
      };
      entry.start();
    });
    unzip.register(UnzipInflate);

    streamZipFile(file, unzip, (bytesRead) => {
      progress.bytesRead = bytesRead;
      emitProgress("reading");
    }).catch(reject).finally(() => {
      if (!foundExportXml) reject(new Error("这个 zip 里没有找到 Apple 健康的 export.xml。"));
    });
  });

  const dailyActivities = [...daily.values()]
    .map(applyPreferredSourceMetrics)
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((item) => ({
      date: item.date,
      source: "apple_health",
      steps: Math.round(item.steps),
      activeCalories: roundOne(item.activeCalories),
      totalCalories: roundOne(item.totalCalories),
      exerciseMinutes: roundOne(item.exerciseMinutes),
      standHours: roundOne(item.standHours),
      distanceKm: roundTwo(item.distanceKm),
      floors: roundOne(item.floors),
      restingHeartRate: average(item.restingHeartRateValues),
      hrvMs: average(item.hrvValues),
      sleepMinutes: roundOne(item.sleepMinutes),
      rawMetrics: finalizeRawMetrics(item.rawMetrics),
      note: "来自 Apple 健康历史导出。",
    }));

  const dates = dailyActivities.map((item) => item.date);
  return {
    dailyActivities,
    workouts,
    summary: {
      dateCount: dailyActivities.length,
      workoutCount: workouts.length,
      firstDate: dates[0] || "",
      lastDate: dates[dates.length - 1] || "",
      cutoffDate,
    },
  };
}

async function streamZipFile(file: File, unzip: Unzip, onProgress?: (bytesRead: number) => void) {
  const stream = file.stream?.();
  if (!stream) {
    throw new Error("当前浏览器不支持大文件流式读取，请换 Safari/Chrome 最新版再试。");
  }
  const reader = stream.getReader();
  let bytesRead = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    bytesRead += value.byteLength;
    onProgress?.(bytesRead);
    unzip.push(value, false);
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  unzip.push(new Uint8Array(), true);
}

function parseXmlLines(
  buffer: string,
  daily: Map<string, DailyAccumulator>,
  workouts: ExerciseActivityInput[],
  cutoffDate: string,
  final: boolean,
  progress: { recordsScanned: number; recordsKept: number; workoutsKept: number },
) {
  const lines = buffer.split(/\r?\n/);
  const remainder = final ? "" : lines.pop() || "";
  for (const line of lines) {
    if (line.includes("<Record ")) {
      progress.recordsScanned += 1;
      if (parseRecordLine(line, daily, cutoffDate)) progress.recordsKept += 1;
    }
    if (line.includes("<Workout ")) {
      const attrs = parseAttrs(line);
      if (shouldSkipWorkout(attrs)) continue;
      const workout = parseWorkoutAttrs(attrs);
      if (!cutoffDate || workout.date >= cutoffDate) {
        workouts.push(workout);
        progress.workoutsKept += 1;
      }
    }
  }
  if (final && remainder) {
    if (remainder.includes("<Record ")) {
      progress.recordsScanned += 1;
      if (parseRecordLine(remainder, daily, cutoffDate)) progress.recordsKept += 1;
    }
    if (remainder.includes("<Workout ")) {
      const attrs = parseAttrs(remainder);
      if (shouldSkipWorkout(attrs)) return remainder;
      const workout = parseWorkoutAttrs(attrs);
      if (!cutoffDate || workout.date >= cutoffDate) {
        workouts.push(workout);
        progress.workoutsKept += 1;
      }
    }
  }
  return remainder;
}

function parseRecordLine(line: string, daily: Map<string, DailyAccumulator>, cutoffDate = "") {
  const type = readAttr(line, "type");
  const definition = metricDefinitionsByType.get(type);
  if (!definition) return false;
  const attrs = parseAttrs(line);
  if (shouldSkipDailyRecord(attrs, definition)) return false;

  const quickDate = dateKeyFromAppleDate(attrs.startDate || attrs.creationDate || attrs.endDate);
  if (!quickDate) return false;
  if (cutoffDate && quickDate < cutoffDate) return false;

  const date = quickDate;
  const day = getDay(daily, date);
  const value = Number(attrs.value || 0);

  if (type === "HKCategoryTypeIdentifierSleepAnalysis") {
    if (String(attrs.value || "").includes("Asleep")) {
      const minutes = minutesBetween(attrs.startDate, attrs.endDate);
      day.sleepMinutes += minutes;
      addRawMetric(day, definition, minutes);
    }
    return true;
  }

  if (type === "HKCategoryTypeIdentifierAppleStandHour") {
    if (String(attrs.value || "").includes("Stood")) {
      day.standHours += 1;
      addRawMetric(day, definition, 1);
      addSourceMetric(day, definition, 1, attrs);
    }
    return true;
  }

  const normalizedValue = normalizeMetricValue(value, attrs.unit, definition);
  const metricValue = type === "HKQuantityTypeIdentifierAppleStandTime" ? normalizedValue / 60 : normalizedValue;
  addRawMetric(day, definition, metricValue);
  addSourceMetric(day, definition, metricValue, attrs);

  switch (type) {
    case "HKQuantityTypeIdentifierStepCount":
      day.steps += metricValue;
      break;
    case "HKQuantityTypeIdentifierActiveEnergyBurned":
      day.activeCalories += metricValue;
      day.totalCalories += metricValue;
      break;
    case "HKQuantityTypeIdentifierBasalEnergyBurned":
      day.totalCalories += metricValue;
      break;
    case "HKQuantityTypeIdentifierAppleExerciseTime":
      day.exerciseMinutes += metricValue;
      break;
    case "HKQuantityTypeIdentifierAppleStandTime":
      day.standHours += metricValue;
      break;
    case "HKQuantityTypeIdentifierDistanceWalkingRunning":
      day.distanceKm += metricValue;
      break;
    case "HKQuantityTypeIdentifierDistanceCycling":
      break;
    case "HKQuantityTypeIdentifierFlightsClimbed":
      day.floors += metricValue;
      break;
    case "HKQuantityTypeIdentifierRestingHeartRate":
      if (metricValue) day.restingHeartRateValues.push(metricValue);
      break;
    case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
      if (metricValue) day.hrvValues.push(metricValue);
      break;
  }
  return true;
}

function parseWorkoutAttrs(attrs: Record<string, string>): ExerciseActivityInput {
  const date = dateKeyFromAppleDate(attrs.startDate || attrs.creationDate || attrs.endDate) || new Date().toISOString().slice(0, 10);
  const type = workoutTypeLabel(attrs.workoutActivityType || "");
  const durationMinutes = durationToMinutes(Number(attrs.duration || 0), attrs.durationUnit);
  const distanceKm = distanceToKm(Number(attrs.totalDistance || 0), attrs.totalDistanceUnit);
  const activeCalories = energyToKcal(Number(attrs.totalEnergyBurned || 0), attrs.totalEnergyBurnedUnit);
  const startedAt = appleDateToInput(attrs.startDate) || `${date}T00:00`;

  return {
    date,
    startedAt,
    source: "apple_health",
    externalId: stableExternalId([attrs.sourceName, attrs.startDate, attrs.endDate, attrs.workoutActivityType, attrs.duration, attrs.totalEnergyBurned].join("|")),
    type,
    title: type,
    durationMinutes: roundOne(durationMinutes),
    distanceKm: roundTwo(distanceKm),
    activeCalories: roundOne(activeCalories),
    avgHeartRate: 0,
    maxHeartRate: 0,
    elevationGainM: 0,
    note: `来自 Apple 健康 Workout。${attrs.sourceName ? `来源：${attrs.sourceName}` : ""}`,
  };
}

function shouldSkipDailyRecord(attrs: Record<string, string>, definition: HealthMetricDefinition) {
  const sourceName = attrs.sourceName || "";
  if (!duplicateDailySourcePattern.test(sourceName)) return false;
  return ["活动", "心脏", "活动能力"].includes(definition.category);
}

function shouldSkipWorkout(attrs: Record<string, string>) {
  return duplicateWorkoutSourcePattern.test(attrs.sourceName || "");
}

function parseAttrs(line: string) {
  const attrs: Record<string, string> = {};
  for (const match of line.matchAll(/([A-Za-z0-9_]+)="([^"]*)"/g)) {
    attrs[match[1]] = decodeXml(match[2]);
  }
  return attrs;
}

function readAttr(line: string, name: string) {
  const match = line.match(new RegExp(`${name}="([^"]*)"`));
  return match ? decodeXml(match[1]) : "";
}

function getDay(daily: Map<string, DailyAccumulator>, date: string) {
  const existing = daily.get(date);
  if (existing) return existing;
  const created: DailyAccumulator = {
    date,
    steps: 0,
    activeCalories: 0,
    totalCalories: 0,
    exerciseMinutes: 0,
    standHours: 0,
    distanceKm: 0,
    floors: 0,
    restingHeartRateValues: [],
    hrvValues: [],
    sleepMinutes: 0,
    rawMetrics: {},
    sourceMetrics: {},
  };
  daily.set(date, created);
  return created;
}

function applyPreferredSourceMetrics(day: DailyAccumulator) {
  const steps = preferredSourceValue(day, "HKQuantityTypeIdentifierStepCount");
  const activeCalories = preferredSourceValue(day, "HKQuantityTypeIdentifierActiveEnergyBurned");
  const basalCalories = preferredSourceValue(day, "HKQuantityTypeIdentifierBasalEnergyBurned");
  const exerciseMinutes = preferredSourceValue(day, "HKQuantityTypeIdentifierAppleExerciseTime");
  const standTimeHours = preferredSourceValue(day, "HKQuantityTypeIdentifierAppleStandTime");
  const standHourCount = preferredSourceValue(day, "HKCategoryTypeIdentifierAppleStandHour");
  const walkingRunningKm = preferredSourceValue(day, "HKQuantityTypeIdentifierDistanceWalkingRunning");
  const floors = preferredSourceValue(day, "HKQuantityTypeIdentifierFlightsClimbed");
  const restingHeartRate = preferredSourceValue(day, "HKQuantityTypeIdentifierRestingHeartRate");
  const hrv = preferredSourceValue(day, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN");

  if (steps !== undefined) {
    day.steps = steps;
    setRawMetricValue(day, "HKQuantityTypeIdentifierStepCount", steps);
  }
  if (activeCalories !== undefined) {
    day.activeCalories = activeCalories;
    setRawMetricValue(day, "HKQuantityTypeIdentifierActiveEnergyBurned", activeCalories);
  }
  if (basalCalories !== undefined) {
    setRawMetricValue(day, "HKQuantityTypeIdentifierBasalEnergyBurned", basalCalories);
  }
  if (activeCalories !== undefined || basalCalories !== undefined) {
    day.totalCalories = (activeCalories ?? day.activeCalories) + (basalCalories ?? Math.max(0, day.totalCalories - day.activeCalories));
  }
  if (exerciseMinutes !== undefined) {
    day.exerciseMinutes = exerciseMinutes;
    setRawMetricValue(day, "HKQuantityTypeIdentifierAppleExerciseTime", exerciseMinutes);
  }
  if (standTimeHours !== undefined || standHourCount !== undefined) {
    const standHours = Math.max(standTimeHours || 0, standHourCount || 0);
    day.standHours = standHours;
    if (standTimeHours !== undefined) setRawMetricValue(day, "HKQuantityTypeIdentifierAppleStandTime", standTimeHours);
    if (standHourCount !== undefined) setRawMetricValue(day, "HKCategoryTypeIdentifierAppleStandHour", standHourCount);
  }
  if (walkingRunningKm !== undefined) {
    day.distanceKm = walkingRunningKm;
    setRawMetricValue(day, "HKQuantityTypeIdentifierDistanceWalkingRunning", walkingRunningKm);
  }
  if (floors !== undefined) {
    day.floors = floors;
    setRawMetricValue(day, "HKQuantityTypeIdentifierFlightsClimbed", floors);
  }
  if (restingHeartRate !== undefined) {
    day.restingHeartRateValues = [restingHeartRate];
    setRawMetricValue(day, "HKQuantityTypeIdentifierRestingHeartRate", restingHeartRate);
  }
  if (hrv !== undefined) {
    day.hrvValues = [hrv];
    setRawMetricValue(day, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", hrv);
  }

  return day;
}

function preferredSourceValue(day: DailyAccumulator, type: string) {
  const buckets = day.sourceMetrics[type];
  if (!buckets) return undefined;
  const candidates = Object.values(buckets)
    .map((metric) => ({ metric, value: metricAccumulatorValue(metric) }))
    .filter((item) => Number.isFinite(item.value));
  if (!candidates.length) return undefined;
  candidates.sort((a, b) => {
    if (b.metric.sourcePriority !== a.metric.sourcePriority) return b.metric.sourcePriority - a.metric.sourcePriority;
    if (b.metric.count !== a.metric.count) return b.metric.count - a.metric.count;
    return b.value - a.value;
  });
  return candidates[0].value;
}

function metricAccumulatorValue(metric: MetricAccumulator) {
  if (metric.aggregation === "avg") return metric.count ? metric.sum / metric.count : 0;
  if (metric.aggregation === "latest") return metric.latest;
  return metric.sum;
}

function setRawMetricValue(day: DailyAccumulator, type: string, value: number) {
  const metric = day.rawMetrics[type];
  if (!metric) return;
  metric.sum = value;
  metric.count = value ? 1 : 0;
  metric.latest = value;
}

function addRawMetric(day: DailyAccumulator, definition: HealthMetricDefinition, value: number) {
  if (!Number.isFinite(value)) return;
  const existing = day.rawMetrics[definition.type] || { ...definition, sum: 0, count: 0, latest: 0 };
  existing.sum += value;
  existing.count += 1;
  existing.latest = value;
  day.rawMetrics[definition.type] = existing;
}

function addSourceMetric(day: DailyAccumulator, definition: HealthMetricDefinition, value: number, attrs: Record<string, string>) {
  if (!Number.isFinite(value) || !preferredSourceMetricTypes.has(definition.type)) return;
  const sourceName = attrs.sourceName || attrs.device || "unknown";
  const key = sourceName.toLowerCase();
  day.sourceMetrics[definition.type] = day.sourceMetrics[definition.type] || {};
  const existing = day.sourceMetrics[definition.type][key] || {
    ...definition,
    sum: 0,
    count: 0,
    latest: 0,
    sourceName,
    sourcePriority: sourcePriority(sourceName),
  };
  existing.sum += value;
  existing.count += 1;
  existing.latest = value;
  day.sourceMetrics[definition.type][key] = existing;
}

function sourcePriority(sourceName: string) {
  const normalized = sourceName.toLowerCase();
  if (normalized.includes("watch")) return 100;
  if (normalized.includes("iphone")) return 80;
  if (normalized.includes("apple")) return 70;
  if (normalized.includes("health")) return 60;
  return 10;
}

function finalizeRawMetrics(rawMetrics: Record<string, MetricAccumulator>) {
  return Object.fromEntries(Object.entries(rawMetrics).map(([type, metric]) => {
    const value = metric.aggregation === "avg"
      ? metric.count ? metric.sum / metric.count : 0
      : metric.aggregation === "latest"
        ? metric.latest
        : metric.sum;
    return [type, {
      label: metric.label,
      category: metric.category,
      value: roundMetricValue(value),
      unit: metric.unit,
    }];
  }));
}

function normalizeMetricValue(value: number, unit: string | undefined, definition: HealthMetricDefinition) {
  if (!value) return 0;
  if (definition.converter === "energy") return energyToKcal(value, unit);
  if (definition.converter === "distance") return distanceToKm(value, unit);
  if (definition.converter === "duration") return durationToMinutes(value, unit);
  if (definition.converter === "mass") return massToKg(value, unit);
  if (definition.converter === "percent") return percentValue(value, unit);
  if (definition.converter === "temperature") return temperatureToC(value, unit);
  if (definition.unit === "cm" && unit === "m") return value * 100;
  if (definition.unit === "m" && unit === "km") return value * 1000;
  if (definition.unit === "mL" && unit === "L") return value * 1000;
  if (definition.unit === "mg" && unit === "g") return value * 1000;
  return value;
}

function dateKeyFromAppleDate(value?: string) {
  return value?.slice(0, 10) || "";
}

function appleDateToInput(value?: string) {
  if (!value) return "";
  return value.slice(0, 16).replace(" ", "T");
}

function minutesBetween(start?: string, end?: string) {
  if (!start || !end) return 0;
  const startTime = new Date(start.replace(" ", "T")).getTime();
  const endTime = new Date(end.replace(" ", "T")).getTime();
  if (Number.isNaN(startTime) || Number.isNaN(endTime) || endTime <= startTime) return 0;
  return (endTime - startTime) / 60000;
}

function durationToMinutes(value: number, unit = "min") {
  if (!value) return 0;
  if (unit === "s" || unit === "sec") return value / 60;
  if (unit === "hr" || unit === "h") return value * 60;
  return value;
}

function distanceToKm(value: number, unit = "km") {
  if (!value) return 0;
  if (unit === "m") return value / 1000;
  if (unit === "mi") return value * 1.609344;
  return value;
}

function energyToKcal(value: number, unit = "kcal") {
  if (!value) return 0;
  if (unit === "kJ") return value * 0.239006;
  return value;
}

function massToKg(value: number, unit = "kg") {
  if (!value) return 0;
  if (unit === "g") return value / 1000;
  if (unit === "lb") return value * 0.45359237;
  if (unit === "oz") return value * 0.0283495;
  return value;
}

function percentValue(value: number, unit = "%") {
  if (!value) return 0;
  if (unit === "%" || unit.includes("percent")) return value;
  return value <= 1 ? value * 100 : value;
}

function temperatureToC(value: number, unit = "degC") {
  if (!value) return 0;
  if (unit === "degF" || unit === "°F") return (value - 32) * 5 / 9;
  return value;
}

function average(values: number[]) {
  if (!values.length) return 0;
  return roundOne(values.reduce((sum, value) => sum + value, 0) / values.length);
}

function roundOne(value: number) {
  return Math.round(value * 10) / 10;
}

function roundTwo(value: number) {
  return Math.round(value * 100) / 100;
}

function roundMetricValue(value: number) {
  if (Math.abs(value) >= 1000) return Math.round(value);
  if (Math.abs(value) >= 100) return Math.round(value * 10) / 10;
  return Math.round(value * 100) / 100;
}

function workoutTypeLabel(value: string) {
  return value
    .replace("HKWorkoutActivityType", "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .trim() || "运动";
}

function stableExternalId(value: string) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return `apple-health-${hash.toString(16)}`;
}

function decodeXml(value: string) {
  return value
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&gt;/g, ">")
    .replace(/&lt;/g, "<")
    .replace(/&amp;/g, "&");
}
