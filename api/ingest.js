import { createClient } from "@supabase/supabase-js";

const bucket = process.env.SUPABASE_STORAGE_BUCKET || process.env.VITE_SUPABASE_STORAGE_BUCKET || "meal-photos";

function json(res, status, payload) {
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

function normalizeError(error) {
  if (error instanceof Error) {
    return {
      message: error.message,
      name: error.name,
    };
  }

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
  if (typeof req.body === "string") return JSON.parse(req.body);

  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = Buffer.concat(chunks).toString("utf8");
  return body ? JSON.parse(body) : {};
}

function requireBearer(req) {
  const token = process.env.DIARY_INGEST_TOKEN;
  if (!token) return { ok: false, status: 500, message: "DIARY_INGEST_TOKEN is not configured." };

  const header = req.headers.authorization || "";
  const provided = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  if (provided !== token) return { ok: false, status: 401, message: "Unauthorized." };

  return { ok: true };
}

function contentTypeFor(fileName = "") {
  const ext = fileName.toLowerCase().split(".").pop();
  if (ext === "png") return "image/png";
  if (ext === "webp") return "image/webp";
  if (ext === "heic" || ext === "heif") return "image/heic";
  return "image/jpeg";
}

function safeStorageName(fileName) {
  return String(fileName || "meal-photo.jpg").replace(/[^a-zA-Z0-9._-]/g, "-");
}

function bufferFromDataUrl(dataUrl) {
  const parts = String(dataUrl || "").split(",");
  if (parts.length !== 2) throw new Error("Invalid photo dataUrl.");
  return Buffer.from(parts[1], "base64");
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

async function uploadPhotos(supabase, userId, photos = []) {
  const uploaded = new Map();

  for (const photo of photos) {
    const date = photo.date || new Date().toISOString().slice(0, 10);
    const fileName = safeStorageName(photo.fileName);
    const storagePath = `${userId}/${date}/${fileName}`;
    const contentType = photo.contentType || contentTypeFor(fileName);
    const body = bufferFromDataUrl(photo.dataUrl);
    const { error } = await supabase.storage.from(bucket).upload(storagePath, body, {
      contentType,
      upsert: true,
    });
    if (error) throw error;
    uploaded.set(photo.key, storagePath);
  }

  return uploaded;
}

async function upsertItems(supabase, userId, uploadedPhotos, items = []) {
  let inserted = 0;
  let updated = 0;

  for (const item of items) {
    const sourceId = item.sourceId || item.id;
    if (!sourceId) throw new Error("Each item needs sourceId.");

    const row = {
      user_id: userId,
      source_id: sourceId,
      eaten_on: item.date,
      meal: item.meal,
      name: item.name,
      grams: Number(item.grams || 0),
      calories: Number(item.calories || 0),
      protein: Number(item.protein || 0),
      carbs: Number(item.carbs || 0),
      fat: Number(item.fat || 0),
      fiber: Number(item.fiber || 0),
      note: item.note || null,
      photo_urls: (item.photoKeys || []).map((key) => uploadedPhotos.get(key)).filter(Boolean),
      created_at: item.createdAt || new Date().toISOString(),
    };

    const { data: existing, error: selectError } = await supabase
      .from("food_items")
      .select("id")
      .eq("user_id", userId)
      .eq("source_id", sourceId)
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

  return { inserted, updated };
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("allow", "POST");
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
    const payload = await readJson(req);
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const userId = await resolveUserId(supabase, payload);
    const uploadedPhotos = await uploadPhotos(supabase, userId, payload.photos || []);
    const result = await upsertItems(supabase, userId, uploadedPhotos, payload.items || []);

    return json(res, 200, {
      ok: true,
      inserted: result.inserted,
      updated: result.updated,
      photosUploaded: uploadedPhotos.size,
    });
  } catch (error) {
    const normalized = normalizeError(error);
    return json(res, 500, {
      error: normalized.message,
      details: normalized,
    });
  }
}
