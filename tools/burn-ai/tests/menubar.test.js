import test from "node:test";
import assert from "node:assert/strict";
import { renderMenuBar, swiftBarStatusItemVisibilityKeys } from "../dist/menubar.js";

const codexProvider = {
  usage: {
    provider: "codex",
    source: "test",
    observedAt: "2026-05-08T00:00:00.000Z",
    windows: [
      { name: "five_hour", windowMinutes: 300, usedPercent: 0, resetsAt: "2026-05-08T03:00:00.000Z" },
      { name: "seven_day", windowMinutes: 10080, usedPercent: 35, resetsAt: "2026-05-12T00:00:00.000Z" },
    ],
  },
  analysis: {
    provider: "codex",
    state: "UNDER_BURN",
    profile: "low",
    observedAt: "2026-05-08T00:00:00.000Z",
    fiveHour: { name: "five_hour", windowMinutes: 300, usedPercent: 0, resetsAt: "2026-05-08T03:00:00.000Z" },
    sevenDay: { name: "seven_day", windowMinutes: 10080, usedPercent: 35, resetsAt: "2026-05-12T00:00:00.000Z" },
    target: {
      minPercent: 3,
      maxPercent: 4.2,
      recommendedPercent: 3.8,
      conversionRate: 1,
    },
    message: "Codex 5h usage is below target.",
  },
  meta: {
    source: "test",
    observedAt: "2026-05-08T00:00:00.000Z",
    ageSeconds: 10,
    stale: false,
  },
};

const claudeProvider = {
  usage: {
    provider: "claude",
    source: "test",
    observedAt: "2026-05-08T00:00:00.000Z",
    windows: [
      { name: "five_hour", windowMinutes: 300, usedPercent: 31, resetsAt: "2026-05-08T03:00:00.000Z" },
      { name: "seven_day", windowMinutes: 10080, usedPercent: 69, resetsAt: "2026-05-12T00:00:00.000Z" },
    ],
  },
  analysis: {
    provider: "claude",
    state: "OVER_BURN",
    profile: "low",
    observedAt: "2026-05-08T00:00:00.000Z",
    fiveHour: { name: "five_hour", windowMinutes: 300, usedPercent: 31, resetsAt: "2026-05-08T03:00:00.000Z" },
    sevenDay: { name: "seven_day", windowMinutes: 10080, usedPercent: 69, resetsAt: "2026-05-12T00:00:00.000Z" },
    target: {
      minPercent: 14,
      maxPercent: 20,
      recommendedPercent: 17,
      conversionRate: 1,
    },
    message: "Claude 5h usage is above target.",
  },
  meta: {
    source: "test",
    observedAt: "2026-05-08T00:00:00.000Z",
    ageSeconds: 10,
    stale: false,
  },
};

const snapshot = {
  generatedAt: "2026-05-08T00:00:00.000Z",
  profile: "low",
  providers: [
    claudeProvider,
    codexProvider,
  ],
  issues: [
    {
      provider: "claude",
      severity: "warning",
      code: "CLAUDE_INGEST_MISSING",
      message: "missing",
    },
  ],
};

test("renderMenuBar outputs SwiftBar-compatible status text", () => {
  const output = renderMenuBar(snapshot);

  assert.match(output, /^Codex\(Slow\) 5h 0% \/ 7d 35%  Claude\(Fast\) 5h 31% \/ 7d 69%/);
  assert.match(output, /\n---\n/);
  assert.match(output, /Codex  Slow \| color=#D70015/);
  assert.match(output, /Claude  Fast \| color=#D70015/);
  assert.match(output, /5h usage\s+0%\s+reset/);
  assert.match(output, /7d usage\s+35%\s+reset/);
  assert.match(output, /WARNING  Claude not connected \| color=#D70015/);
  assert.match(output, /Refresh now \| refresh=true/);
});

test("swiftBarStatusItemVisibilityKeys finds hidden status item cache keys", () => {
  const output = `{
    MakePluginExecutable = 1;
    "NSStatusItem Visible Item-0" = 0;
    "NSStatusItem Visible Item-1" = 1;
    "NSStatusItem Preferred Position com.example.one" = 12;
    PluginDirectory = "/tmp/swiftbar";
  }`;

  assert.deepEqual(swiftBarStatusItemVisibilityKeys(output), [
    "NSStatusItem Visible Item-0",
    "NSStatusItem Visible Item-1",
  ]);
});
