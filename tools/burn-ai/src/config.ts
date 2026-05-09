import { readJsonFile, writeJsonAtomic } from "./fs-util.js";
import { buildPaths } from "./paths.js";
import { BurnConfig, ProviderId, RuntimePaths } from "./types.js";

const DEFAULT_PROVIDERS: ProviderId[] = ["codex", "claude"];
const PROVIDERS = new Set<ProviderId>(["codex", "claude"]);

function normalizeProviders(value: unknown): ProviderId[] {
  if (!Array.isArray(value)) {
    return DEFAULT_PROVIDERS;
  }
  const providers = value.filter((item): item is ProviderId => {
    return typeof item === "string" && PROVIDERS.has(item as ProviderId);
  });
  return providers.length > 0 ? [...new Set(providers)] : DEFAULT_PROVIDERS;
}

function envProviders() {
  const raw = process.env.BURN_AI_PROVIDERS;
  if (!raw) {
    return null;
  }
  return normalizeProviders(raw.split(",").map((item) => item.trim()));
}

export function defaultConfig(): BurnConfig {
  return { providers: DEFAULT_PROVIDERS };
}

export function readConfig(paths: RuntimePaths = buildPaths()): BurnConfig {
  const fromEnv = envProviders();
  if (fromEnv) {
    return { providers: fromEnv };
  }

  const fileConfig = readJsonFile<Partial<BurnConfig>>(paths.configFile);
  if (!fileConfig) {
    return defaultConfig();
  }
  return {
    providers: normalizeProviders(fileConfig.providers),
  };
}

export function ensureConfig(paths: RuntimePaths = buildPaths()) {
  if (readJsonFile<Partial<BurnConfig>>(paths.configFile)) {
    return false;
  }
  writeJsonAtomic(paths.configFile, defaultConfig());
  return true;
}
