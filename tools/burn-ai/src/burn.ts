import { findWindow } from "./usage.js";
import { BurnAnalysis, BurnProfile, BurnState, ProviderId, ProviderUsage } from "./types.js";

const PROFILE_FACTORS: Record<BurnProfile, { min: number; max: number }> = {
  low: { min: 0.8, max: 1.1 },
  high: { min: 0.9, max: 1.35 },
};

function round(value: number) {
  return Math.round(value * 10) / 10;
}

function minutesUntil(iso: string, nowMs: number) {
  return Math.max(0, (Date.parse(iso) - nowMs) / 60_000);
}

function median(values: number[]) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

export function estimateConversionRate(samples: ProviderUsage[]): number | null {
  const usable = [...samples]
    .sort((left, right) => Date.parse(left.observedAt) - Date.parse(right.observedAt))
    .map((sample) => ({
      five: findWindow(sample, "five_hour")?.usedPercent,
      seven: findWindow(sample, "seven_day")?.usedPercent,
    }))
    .filter((item): item is { five: number; seven: number } => {
      return typeof item.five === "number" && typeof item.seven === "number";
    });

  const rates: number[] = [];
  for (let i = 1; i < usable.length; i += 1) {
    const deltaFive = usable[i].five - usable[i - 1].five;
    const deltaSeven = usable[i].seven - usable[i - 1].seven;
    if (deltaFive > 0 && deltaSeven >= 0) {
      rates.push(deltaSeven / deltaFive);
    }
  }

  if (rates.length < 2) {
    return null;
  }
  const value = median(rates.filter((rate) => Number.isFinite(rate) && rate > 0));
  return Number.isFinite(value) && value > 0 ? value : null;
}

function messageForState(provider: ProviderId, state: BurnState, fiveUsed?: number, target?: { min: number; max: number }) {
  const label = provider === "claude" ? "Claude" : "Codex";
  if (state === "LIMIT_RISK") {
    return `${label} usage is close to a plan limit. Consider switching provider or lowering intensity.`;
  }
  if (!target || fiveUsed === undefined) {
    return `${label} usage is visible, but more samples are needed before dynamic burn advice is available.`;
  }
  if (state === "UNDER_BURN") {
    return `${label} 5h usage is below target (${round(fiveUsed)}%, target ${round(target.min)}%-${round(target.max)}%).`;
  }
  if (state === "OVER_BURN") {
    return `${label} 5h usage is above target (${round(fiveUsed)}%, target ${round(target.min)}%-${round(target.max)}%).`;
  }
  return `${label} burn pace is on track (${round(fiveUsed)}%, target ${round(target.min)}%-${round(target.max)}%).`;
}

export function analyzeUsage(
  usage: ProviderUsage,
  samples: ProviderUsage[],
  profile: BurnProfile = "low",
  now = new Date(),
): BurnAnalysis {
  const fiveHour = findWindow(usage, "five_hour");
  const sevenDay = findWindow(usage, "seven_day");
  if (!fiveHour || !sevenDay) {
    return {
      provider: usage.provider,
      state: "RAW",
      profile,
      observedAt: usage.observedAt,
      message: `${usage.provider}: missing 5h or 7d usage window.`,
    };
  }

  if (fiveHour.usedPercent >= 90 || sevenDay.usedPercent >= 90) {
    return {
      provider: usage.provider,
      state: "LIMIT_RISK",
      profile,
      observedAt: usage.observedAt,
      fiveHour,
      sevenDay,
      message: messageForState(usage.provider, "LIMIT_RISK"),
    };
  }

  const conversionRate = estimateConversionRate(samples);
  if (conversionRate === null) {
    return {
      provider: usage.provider,
      state: "RAW",
      profile,
      observedAt: usage.observedAt,
      fiveHour,
      sevenDay,
      message: messageForState(usage.provider, "RAW"),
    };
  }

  const remainingSeven = Math.max(0, 100 - sevenDay.usedPercent);
  const remainingSlots = Math.max(1, minutesUntil(sevenDay.resetsAt, now.getTime()) / 300);
  const weeklyBudgetPerSlot = remainingSeven / remainingSlots;
  const recommendedPercent = Math.min(100, weeklyBudgetPerSlot / conversionRate);
  const factors = PROFILE_FACTORS[profile];
  const target = {
    minPercent: Math.min(100, recommendedPercent * factors.min),
    maxPercent: Math.min(100, recommendedPercent * factors.max),
    recommendedPercent,
    conversionRate,
  };

  let state: BurnState = "ON_TRACK";
  if (fiveHour.usedPercent < target.minPercent) {
    state = "UNDER_BURN";
  } else if (fiveHour.usedPercent > target.maxPercent) {
    state = "OVER_BURN";
  }

  return {
    provider: usage.provider,
    state,
    profile,
    observedAt: usage.observedAt,
    fiveHour,
    sevenDay,
    target,
    message: messageForState(usage.provider, state, fiveHour.usedPercent, {
      min: target.minPercent,
      max: target.maxPercent,
    }),
  };
}
