import test from "node:test";
import assert from "node:assert/strict";
import { renderMenuBar } from "../dist/menubar.js";

const snapshot = {
  generatedAt: "2026-05-08T00:00:00.000Z",
  profile: "low",
  providers: [
    {
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
    },
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

  assert.match(output, /^Burn LOW Codex 5h 0% \/ 7d 35%/);
  assert.match(output, /\n---\n/);
  assert.match(output, /Codex  LOW \| color=#B45309/);
  assert.match(output, /5h usage\s+0%\s+reset/);
  assert.match(output, /7d usage\s+35%\s+reset/);
  assert.match(output, /WARNING  Claude not connected \| color=#B45309/);
  assert.match(output, /Refresh now \| refresh=true/);
});
