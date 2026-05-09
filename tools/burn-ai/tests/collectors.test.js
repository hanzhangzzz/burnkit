import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { usageFromClaudeStatusLine } from "../dist/claude.js";
import { collectCodexUsage } from "../dist/codex.js";

test("usageFromClaudeStatusLine normalizes status line rate limits", () => {
  const usage = usageFromClaudeStatusLine({
    rate_limits: {
      five_hour: { used_percentage: 42, resets_at: "2026-05-08T02:00:00Z" },
      seven_day: { used_percentage: 18, resets_at: "2026-05-12T00:00:00Z" },
    },
  });

  assert.equal(usage.provider, "claude");
  assert.equal(usage.windows[0].usedPercent, 42);
  assert.equal(usage.windows[1].windowMinutes, 10080);
});

test("usageFromClaudeStatusLine rejects missing usage", () => {
  assert.throws(() => usageFromClaudeStatusLine({}), /rate_limits/);
});

test("collectCodexUsage reads latest payload.rate_limits from jsonl", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-codex-"));
  fs.mkdirSync(path.join(dir, "sessions"), { recursive: true });
  fs.writeFileSync(
    path.join(dir, "sessions", "rollout.jsonl"),
    [
      JSON.stringify({
        timestamp: "2026-05-08T00:00:00.000Z",
        type: "event_msg",
        payload: {
          type: "token_count",
          rate_limits: {
            primary: { used_percent: 12, window_minutes: 300, resets_at: 1778205600 },
            secondary: { used_percent: 34, window_minutes: 10080, resets_at: 1778544000 },
            plan_type: "pro",
          },
        },
      }),
      "",
    ].join("\n"),
    "utf8",
  );

  const usage = collectCodexUsage(dir);
  assert.equal(usage.provider, "codex");
  assert.equal(usage.planType, "pro");
  assert.equal(usage.windows[0].usedPercent, 12);
});

test("collectCodexUsage ignores non-session jsonl files", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-codex-"));
  fs.mkdirSync(path.join(dir, "sessions"), { recursive: true });
  fs.mkdirSync(path.join(dir, ".tmp", "plugins"), { recursive: true });
  fs.writeFileSync(
    path.join(dir, ".tmp", "plugins", "fixture.jsonl"),
    `${JSON.stringify({
      timestamp: "2026-05-09T00:00:00.000Z",
      payload: {
        rate_limits: {
          primary: { used_percent: 99, window_minutes: 300, resets_at: 1778205600 },
          secondary: { used_percent: 99, window_minutes: 10080, resets_at: 1778544000 },
        },
      },
    })}\n`,
    "utf8",
  );
  fs.writeFileSync(
    path.join(dir, "sessions", "rollout.jsonl"),
    `${JSON.stringify({
      timestamp: "2026-05-08T00:00:00.000Z",
      payload: {
        rate_limits: {
          primary: { used_percent: 12, window_minutes: 300, resets_at: 1778205600 },
          secondary: { used_percent: 34, window_minutes: 10080, resets_at: 1778544000 },
        },
      },
    })}\n`,
    "utf8",
  );

  const usage = collectCodexUsage(dir);
  assert.equal(usage.windows[0].usedPercent, 12);
});
