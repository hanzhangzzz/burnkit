import test from "node:test";
import assert from "node:assert/strict";
import { analyzeUsage, estimateConversionRate } from "../dist/burn.js";

const baseUsage = {
  provider: "claude",
  source: "test",
  observedAt: "2026-05-08T00:00:00.000Z",
  planType: null,
  windows: [
    { name: "five_hour", windowMinutes: 300, usedPercent: 30, resetsAt: "2026-05-08T02:00:00.000Z" },
    { name: "seven_day", windowMinutes: 10080, usedPercent: 35, resetsAt: "2026-05-12T00:00:00.000Z" },
  ],
};

const samples = [
  {
    ...baseUsage,
    observedAt: "2026-05-07T22:00:00.000Z",
    windows: [
      { name: "five_hour", windowMinutes: 300, usedPercent: 10, resetsAt: "2026-05-08T02:00:00.000Z" },
      { name: "seven_day", windowMinutes: 10080, usedPercent: 33, resetsAt: "2026-05-12T00:00:00.000Z" },
    ],
  },
  {
    ...baseUsage,
    observedAt: "2026-05-07T23:00:00.000Z",
    windows: [
      { name: "five_hour", windowMinutes: 300, usedPercent: 20, resetsAt: "2026-05-08T02:00:00.000Z" },
      { name: "seven_day", windowMinutes: 10080, usedPercent: 34, resetsAt: "2026-05-12T00:00:00.000Z" },
    ],
  },
  baseUsage,
];

test("estimateConversionRate learns 7d delta per 5h delta", () => {
  assert.equal(estimateConversionRate(samples), 0.1);
});

test("analyzeUsage returns RAW during cold start", () => {
  const analysis = analyzeUsage(baseUsage, [baseUsage], "low", new Date("2026-05-08T00:00:00.000Z"));
  assert.equal(analysis.state, "RAW");
});

test("analyzeUsage marks limit risk before dynamic advice", () => {
  const usage = {
    ...baseUsage,
    windows: [
      { name: "five_hour", windowMinutes: 300, usedPercent: 91, resetsAt: "2026-05-08T02:00:00.000Z" },
      { name: "seven_day", windowMinutes: 10080, usedPercent: 35, resetsAt: "2026-05-12T00:00:00.000Z" },
    ],
  };
  const analysis = analyzeUsage(usage, samples, "high", new Date("2026-05-08T00:00:00.000Z"));
  assert.equal(analysis.state, "LIMIT_RISK");
});

test("analyzeUsage uses different low/high target ranges", () => {
  const low = analyzeUsage(baseUsage, samples, "low", new Date("2026-05-08T00:00:00.000Z"));
  const high = analyzeUsage(baseUsage, samples, "high", new Date("2026-05-08T00:00:00.000Z"));
  assert.ok(low.target.maxPercent < high.target.maxPercent);
});
