/// <reference lib="webworker" />

import { parseAppleHealthExport } from "./appleHealth";

self.onmessage = async (event: MessageEvent<{ file: File; cutoffDate: string }>) => {
  const { cutoffDate, file } = event.data;
  try {
    const result = await parseAppleHealthExport(file, {
      cutoffDate,
      onProgress: (progress) => {
        self.postMessage({ type: "progress", progress });
      },
    });
    self.postMessage({ type: "done", result });
  } catch (error) {
    const message = error instanceof Error
      ? `${error.name}: ${error.message}${error.stack ? `\n${error.stack}` : ""}`
      : String(error || "未知错误");
    self.postMessage({ type: "error", message });
  }
};

export {};
