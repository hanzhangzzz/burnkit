import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { buildPaths } from "../dist/paths.js";
import { maybePromptForStar } from "../dist/star.js";

test("maybePromptForStar asks once and stars BurnKit when accepted", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-star-"));
  const paths = buildPaths(home);
  const prompts = [];
  const starredRepos = [];

  const messages = maybePromptForStar(paths, {
    dryRun: false,
    isInteractive: true,
    confirmStar: (prompt) => {
      prompts.push(prompt);
      return true;
    },
    starRepo: (repo) => {
      starredRepos.push(repo);
    },
  });

  assert.deepEqual(starredRepos, ["hanzhangzzz/burnkit"]);
  assert.equal(prompts.length, 1);
  assert.match(prompts[0], /Enjoying BurnKit\? Star it on GitHub\? \[Y\/n\]/);
  assert.ok(messages.some((message) => message.includes("Starred BurnKit on GitHub.")));
  assert.equal(JSON.parse(fs.readFileSync(paths.starPromptFile, "utf8")).response, "accepted");

  maybePromptForStar(paths, {
    dryRun: false,
    isInteractive: true,
    confirmStar: () => {
      throw new Error("should not prompt twice");
    },
    starRepo: () => {
      throw new Error("should not star twice");
    },
  });
});

test("maybePromptForStar records declined prompts without calling gh", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-star-"));
  const paths = buildPaths(home);

  const messages = maybePromptForStar(paths, {
    dryRun: false,
    isInteractive: true,
    confirmStar: () => false,
    starRepo: () => {
      throw new Error("should not star when declined");
    },
  });

  assert.ok(messages.some((message) => message.includes("Skipped GitHub star prompt.")));
  assert.equal(JSON.parse(fs.readFileSync(paths.starPromptFile, "utf8")).response, "declined");
});

test("maybePromptForStar skips dry-run, CI, and non-interactive installs", () => {
  for (const options of [
    { dryRun: true, isInteractive: true, env: {} },
    { dryRun: false, isInteractive: false, env: {} },
    { dryRun: false, isInteractive: true, env: { CI: "true" } },
  ]) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-star-"));
    const paths = buildPaths(home);

    const messages = maybePromptForStar(paths, {
      ...options,
      confirmStar: () => {
        throw new Error("should not prompt");
      },
      starRepo: () => {
        throw new Error("should not star");
      },
    });

    assert.deepEqual(messages, []);
    assert.equal(fs.existsSync(paths.starPromptFile), false);
  }
});
