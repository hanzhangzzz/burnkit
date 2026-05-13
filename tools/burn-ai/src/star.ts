import { execFileSync } from "node:child_process";
import { readJsonFile, writeJsonAtomic } from "./fs-util.js";
import { RuntimePaths } from "./types.js";

const REPO = "hanzhangzzz/burnkit";
const PROMPT = "[burn-ai] Enjoying BurnKit? Star it on GitHub? [Y/n] ";

interface StarPromptState {
  repo: string;
  promptedAt: string;
  response: "accepted" | "declined";
  outcome: "starred" | "skipped" | "failed";
  error?: string;
}

interface StarPromptOptions {
  dryRun: boolean;
  isInteractive?: boolean;
  env?: Record<string, string | undefined>;
  canStarWithGh?: boolean | (() => boolean);
  confirmStar?: (prompt: string) => boolean;
  starRepo?: (repo: string) => void;
  now?: () => Date;
}

function defaultIsInteractive() {
  return Boolean(process.stdin.isTTY && process.stdout.isTTY);
}

function defaultConfirmStar(prompt: string) {
  if (!defaultIsInteractive()) {
    return false;
  }

  try {
    const answer = execFileSync(
      "/bin/sh",
      [
        "-c",
        'printf "%s" "$1" > /dev/tty; IFS= read -r answer < /dev/tty; printf "%s" "$answer"',
        "burn-ai-star-prompt",
        prompt,
      ],
      { encoding: "utf8" },
    ).trim().toLowerCase();
    return answer === "" || answer === "y" || answer === "yes";
  } catch {
    return false;
  }
}

export function ghStarArgs(repo: string) {
  return [
    "api",
    "--method",
    "PUT",
    `/user/starred/${repo}`,
    "--silent",
  ];
}

export function ghAuthStatusArgs() {
  return ["auth", "status", "-h", "github.com"];
}

function commandErrorMessage(error: unknown) {
  if (error && typeof error === "object") {
    const stderr = (error as { stderr?: Buffer | string }).stderr;
    if (Buffer.isBuffer(stderr)) {
      const message = stderr.toString("utf8").trim();
      if (message) {
        return message;
      }
    }
    if (typeof stderr === "string" && stderr.trim()) {
      return stderr.trim();
    }
  }
  return error instanceof Error ? error.message : String(error);
}

function defaultStarRepo(repo: string) {
  execFileSync("gh", ghStarArgs(repo), { stdio: "pipe" });
}

function defaultCanStarWithGh() {
  try {
    execFileSync("gh", ghAuthStatusArgs(), { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function canStarWithGh(options: StarPromptOptions) {
  if (typeof options.canStarWithGh === "boolean") {
    return options.canStarWithGh;
  }
  if (typeof options.canStarWithGh === "function") {
    return options.canStarWithGh();
  }
  return defaultCanStarWithGh();
}

function hasPromptState(paths: RuntimePaths) {
  const state = readJsonFile<StarPromptState>(paths.starPromptFile);
  return state?.repo === REPO && (state.outcome === "starred" || state.outcome === "skipped");
}

export function maybePromptForStar(paths: RuntimePaths, options: StarPromptOptions) {
  const env = options.env ?? process.env;
  if (options.dryRun || env.CI || options.isInteractive === false || hasPromptState(paths)) {
    return [];
  }
  if (options.isInteractive === undefined && !defaultIsInteractive()) {
    return [];
  }
  if (!canStarWithGh(options)) {
    return [];
  }

  const confirmStar = options.confirmStar ?? defaultConfirmStar;
  const starRepo = options.starRepo ?? defaultStarRepo;
  const now = options.now ?? (() => new Date());
  const accepted = confirmStar(PROMPT);
  const state: StarPromptState = {
    repo: REPO,
    promptedAt: now().toISOString(),
    response: accepted ? "accepted" : "declined",
    outcome: accepted ? "starred" : "skipped",
  };

  if (!accepted) {
    writeJsonAtomic(paths.starPromptFile, state);
    return ["Skipped GitHub star prompt."];
  }

  try {
    starRepo(REPO);
    writeJsonAtomic(paths.starPromptFile, state);
    return ["Starred BurnKit on GitHub."];
  } catch (error) {
    state.outcome = "failed";
    state.error = commandErrorMessage(error);
    writeJsonAtomic(paths.starPromptFile, state);
    return [`Could not star BurnKit with gh: ${state.error}`];
  }
}
