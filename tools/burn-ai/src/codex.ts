import fs from "node:fs";
import path from "node:path";
import { isDir } from "./fs-util.js";
import { makeProviderUsage, normalizeWindow } from "./usage.js";
import { ProviderUsage } from "./types.js";

interface CodexCandidate {
  usage: ProviderUsage;
  observedMs: number;
}

function walkJsonlFiles(dir: string, result: string[] = []): string[] {
  if (!isDir(dir)) {
    return result;
  }

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "node_modules" || entry.name === ".git") {
        continue;
      }
      walkJsonlFiles(fullPath, result);
    } else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
      result.push(fullPath);
    }
  }

  return result;
}

function parseObservedMs(raw: unknown, fallbackMs: number) {
  if (typeof raw === "string") {
    const parsed = Date.parse(raw);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return raw > 10_000_000_000 ? raw : raw * 1000;
  }
  return fallbackMs;
}

export function usageFromCodexRateLimits(
  rateLimits: unknown,
  options: { observedAt?: string; source: string },
): ProviderUsage | null {
  if (rateLimits === null || typeof rateLimits !== "object") {
    return null;
  }
  const record = rateLimits as Record<string, unknown>;
  const fiveHour = normalizeWindow("five_hour", record.primary, 300);
  const sevenDay = normalizeWindow("seven_day", record.secondary, 10080);
  if (!fiveHour || !sevenDay) {
    return null;
  }

  return makeProviderUsage({
    provider: "codex",
    source: options.source,
    observedAt: options.observedAt,
    planType: typeof record.plan_type === "string" ? record.plan_type : null,
    fiveHour,
    sevenDay,
  });
}

function latestCandidateFromFile(file: string): CodexCandidate | null {
  const stat = fs.statSync(file);
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);

  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const line = lines[i]?.trim();
    if (!line || !line.includes("rate_limits")) {
      continue;
    }

    try {
      const parsed = JSON.parse(line) as Record<string, unknown>;
      const payload = parsed.payload as Record<string, unknown> | undefined;
      const rateLimits = payload?.rate_limits ?? parsed.rate_limits;
      const observedMs = parseObservedMs(parsed.timestamp ?? parsed.ts, stat.mtimeMs);
      const usage = usageFromCodexRateLimits(rateLimits, {
        source: file,
        observedAt: new Date(observedMs).toISOString(),
      });
      if (usage) {
        return { usage, observedMs };
      }
    } catch {
      continue;
    }
  }

  return null;
}

export function collectCodexUsage(codexHome = path.join(process.env.HOME ?? "", ".codex")) {
  if (!isDir(codexHome)) {
    throw new Error(`Codex usage unavailable: ${codexHome} does not exist`);
  }

  const candidates = walkJsonlFiles(codexHome)
    .map((file) => {
      try {
        return latestCandidateFromFile(file);
      } catch {
        return null;
      }
    })
    .filter((item): item is CodexCandidate => item !== null)
    .sort((left, right) => right.observedMs - left.observedMs);

  if (candidates.length === 0) {
    throw new Error(
      "Codex usage unavailable: no local JSONL entry with payload.rate_limits was found. Run Codex CLI/App once and try again.",
    );
  }

  return candidates[0].usage;
}
