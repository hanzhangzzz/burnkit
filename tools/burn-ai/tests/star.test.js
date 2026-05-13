import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { buildPaths } from "../dist/paths.js";
import { ghAuthStatusArgs, ghStarArgs, maybePromptForStar } from "../dist/star.js";

test("maybePromptForStar asks once and stars BurnKit when accepted", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-star-"));
  const paths = buildPaths(home);
  const prompts = [];
  const starredRepos = [];

  const messages = maybePromptForStar(paths, {
    dryRun: false,
    isInteractive: true,
    canStarWithGh: true,
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
    canStarWithGh: true,
    confirmStar: () => false,
    starRepo: () => {
      throw new Error("should not star when declined");
    },
  });

  assert.ok(messages.some((message) => message.includes("Skipped GitHub star prompt.")));
  assert.equal(JSON.parse(fs.readFileSync(paths.starPromptFile, "utf8")).response, "declined");
});

test("ghStarArgs uses GitHub API because gh has no repo star subcommand", () => {
  assert.deepEqual(ghStarArgs("hanzhangzzz/burnkit"), [
    "api",
    "--method",
    "PUT",
    "/user/starred/hanzhangzzz/burnkit",
    "--silent",
  ]);
});

test("ghAuthStatusArgs checks login before asking for a star", () => {
  assert.deepEqual(ghAuthStatusArgs(), ["auth", "status", "-h", "github.com"]);
});

test("maybePromptForStar skips when gh is missing or not logged in", () => {
  for (const preflight of [false, () => false]) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-star-"));
    const paths = buildPaths(home);

    const messages = maybePromptForStar(paths, {
      dryRun: false,
      isInteractive: true,
      canStarWithGh: preflight,
      confirmStar: () => {
        throw new Error("should not ask when gh preflight fails");
      },
      starRepo: () => {
        throw new Error("should not call gh when preflight fails");
      },
    });

    assert.deepEqual(messages, []);
    assert.equal(fs.existsSync(paths.starPromptFile), false);
  }
});

test("maybePromptForStar retries when the previous star attempt failed", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "burn-ai-star-"));
  const paths = buildPaths(home);
  fs.mkdirSync(path.dirname(paths.starPromptFile), { recursive: true });
  fs.writeFileSync(paths.starPromptFile, JSON.stringify({
    repo: "hanzhangzzz/burnkit",
    promptedAt: "2026-05-13T00:00:00.000Z",
    response: "accepted",
    outcome: "failed",
    error: "Command failed: gh repo star hanzhangzzz/burnkit",
  }));

  let prompted = false;
  let starred = false;
  maybePromptForStar(paths, {
    dryRun: false,
    isInteractive: true,
    canStarWithGh: true,
    confirmStar: () => {
      prompted = true;
      return true;
    },
    starRepo: () => {
      starred = true;
    },
  });

  assert.equal(prompted, true);
  assert.equal(starred, true);
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
