import fs from "node:fs/promises";

const endpoint = process.env.DIARY_INGEST_ENDPOINT || "https://diet-cloud.vercel.app/api/ingest";
const token = process.env.DIARY_INGEST_TOKEN;
const inputFile = process.argv[2];

if (!token) {
  console.error("Missing DIARY_INGEST_TOKEN.");
  process.exit(1);
}

if (!inputFile) {
  console.error("Usage: DIARY_INGEST_TOKEN=... node scripts/send-ingest.mjs payload.json");
  process.exit(1);
}

const body = await fs.readFile(inputFile, "utf8");
const response = await fetch(endpoint, {
  method: "POST",
  headers: {
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
  },
  body,
});

const text = await response.text();
if (!response.ok) {
  console.error(text);
  process.exit(1);
}

console.log(text);
