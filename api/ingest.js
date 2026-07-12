import { requireIngestToken, createServiceRoleClient, resolveTrustedUserId, IngestAuthError, errorCodeFor, respondError } from "./_lib/ingestAuth.js";

const bucket = process.env.SUPABASE_STORAGE_BUCKET || process.env.VITE_SUPABASE_STORAGE_BUCKET || "meal-photos";

function json(res, status, payload) {
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

async function readJson(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string") return JSON.parse(req.body);

  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = Buffer.concat(chunks).toString("utf8");
  return body ? JSON.parse(body) : {};
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
  if (parts.length !== 2) throw new IngestAuthError(400, "Invalid photo dataUrl.");
  return Buffer.from(parts[1], "base64");
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
    if (!sourceId) throw new IngestAuthError(400, "Each item needs sourceId.");
    if (!item.date) throw new IngestAuthError(400, `Item ${sourceId} needs date.`);
    if (!item.meal) throw new IngestAuthError(400, `Item ${sourceId} needs meal.`);
    if (!item.name) throw new IngestAuthError(400, `Item ${sourceId} needs name.`);

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
  if (req.method === "OPTIONS") {
    res.setHeader("access-control-allow-methods", "POST, OPTIONS");
    res.setHeader("access-control-allow-headers", "authorization, content-type");
    return json(res, 204, {});
  }

  if (req.method !== "POST") {
    res.setHeader("allow", "POST, OPTIONS");
    return json(res, 405, { error: "Method not allowed.", code: errorCodeFor(405) });
  }

  const auth = requireIngestToken(req);
  if (!auth.ok) return json(res, auth.status, { error: auth.message, code: auth.code || errorCodeFor(auth.status) });

  try {
    const payload = await readJson(req);
    if (!payload || typeof payload !== "object") throw new IngestAuthError(400, "Request body must be a JSON object.");
    if (payload.items !== undefined && !Array.isArray(payload.items)) throw new IngestAuthError(400, "items must be an array.");
    if (payload.photos !== undefined && !Array.isArray(payload.photos)) throw new IngestAuthError(400, "photos must be an array.");

    const supabase = createServiceRoleClient();
    const userId = await resolveTrustedUserId(supabase, payload);
    const uploadedPhotos = await uploadPhotos(supabase, userId, payload.photos || []);
    const result = await upsertItems(supabase, userId, uploadedPhotos, payload.items || []);

    return json(res, 200, {
      ok: true,
      inserted: result.inserted,
      updated: result.updated,
      photosUploaded: uploadedPhotos.size,
    });
  } catch (error) {
    return respondError(res, error, "ingest");
  }
}
