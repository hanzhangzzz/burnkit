import fs from "node:fs";
import { makeProviderUsage, normalizeWindow } from "./usage.js";
import { ProviderUsage } from "./types.js";

export function usageFromClaudeStatusLine(input: unknown): ProviderUsage {
  if (input === null || typeof input !== "object") {
    throw new Error("Claude status line input must be a JSON object");
  }
  const record = input as Record<string, unknown>;
  const rateLimits = record.rate_limits as Record<string, unknown> | undefined;
  if (!rateLimits || typeof rateLimits !== "object") {
    throw new Error("Claude usage unavailable: status line input has no rate_limits field");
  }

  const fiveHour = normalizeWindow("five_hour", rateLimits.five_hour, 300);
  const sevenDay = normalizeWindow("seven_day", rateLimits.seven_day, 10080);
  if (!fiveHour || !sevenDay) {
    throw new Error("Claude usage unavailable: missing five_hour or seven_day rate limit window");
  }

  return makeProviderUsage({
    provider: "claude",
    source: "claude_statusline_stdin",
    fiveHour,
    sevenDay,
  });
}

export function readStdin(): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

export function readClaudeSettings(file: string): Record<string, unknown> | null {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8")) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function getClaudeStatusLineCommand(settings: Record<string, unknown> | null): string | null {
  const statusLine = settings?.statusLine;
  if (statusLine && typeof statusLine === "object") {
    const command = (statusLine as Record<string, unknown>).command;
    return typeof command === "string" ? command : null;
  }
  return null;
}
