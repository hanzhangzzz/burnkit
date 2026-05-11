import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { ensureDir, isFile } from "./fs-util.js";
import { formatDurationUntil, formatProviderLabel } from "./format.js";
import { buildPaths } from "./paths.js";
import { loadDisplayStatusSnapshot } from "./runtime.js";
import { BurnState, RuntimePaths, StatusSnapshot } from "./types.js";

const MARKER = "burn-ai managed SwiftBar plugin";
const SWIFTBAR_APP_PATHS = ["/Applications/SwiftBar.app", path.join(process.env.HOME ?? "", "Applications", "SwiftBar.app")];

const STATE_LABEL: Record<BurnState, string> = {
  RAW: "Wait",
  UNDER_BURN: "Slow",
  ON_TRACK: "OK",
  OVER_BURN: "Fast",
  LIMIT_RISK: "Limit",
};

const ALERT_COLOR = "#D70015";
const OK_COLOR = "#248A3D";
const RAW_COLOR = "#6B7280";

const STATE_COLOR: Record<BurnState, string> = {
  RAW: RAW_COLOR,
  UNDER_BURN: ALERT_COLOR,
  ON_TRACK: OK_COLOR,
  OVER_BURN: ALERT_COLOR,
  LIMIT_RISK: ALERT_COLOR,
};

const TEXT_COLOR = "#111827";
const MUTED_COLOR = RAW_COLOR;
const ROW_FONT = "Menlo";
const TITLE_PROVIDER_ORDER = ["codex", "claude"];

function appCliPath(paths: RuntimePaths) {
  return path.join(paths.stateDir, "app", "dist", "cli.js");
}

function configuredSwiftBarPluginDir(paths: RuntimePaths) {
  try {
    const configured = execFileSync("defaults", ["read", "com.ameba.SwiftBar", "PluginDirectory"], {
      encoding: "utf8",
    }).trim();
    return configured || paths.swiftBarPluginDir;
  } catch {
    return paths.swiftBarPluginDir;
  }
}

export function swiftBarPluginPath(paths: RuntimePaths = buildPaths()) {
  const pluginDir = configuredSwiftBarPluginDir(paths);
  return {
    dir: pluginDir,
    file: path.join(pluginDir, "burn-ai.1m.js"),
  };
}

export function isSwiftBarInstalled() {
  return SWIFTBAR_APP_PATHS.some((appPath) => appPath && fs.existsSync(appPath));
}

function swiftBarAppPath() {
  return SWIFTBAR_APP_PATHS.find((appPath) => appPath && fs.existsSync(appPath)) ?? null;
}

function brewPath() {
  const candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"];
  const found = candidates.find((candidate) => fs.existsSync(candidate));
  if (found) {
    return found;
  }
  try {
    return execFileSync("which", ["brew"], { encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

export function ensureSwiftBarInstalled(options: { dryRun?: boolean } = {}) {
  const dryRun = options.dryRun ?? false;
  if (isSwiftBarInstalled()) {
    return ["SwiftBar already installed."];
  }

  const brew = brewPath();
  if (!brew) {
    return ["SwiftBar is missing and Homebrew is unavailable; install SwiftBar manually, then run burn-ai menubar install."];
  }

  if (dryRun) {
    return [`[dry-run] would install SwiftBar with ${brew} install --cask swiftbar`];
  }

  execFileSync(brew, ["install", "--cask", "swiftbar"], {
    env: { ...process.env, HOMEBREW_NO_AUTO_UPDATE: "1" },
    stdio: "inherit",
  });
  return ["Installed SwiftBar with Homebrew cask."];
}

export function openSwiftBar() {
  const appPath = swiftBarAppPath();
  if (!appPath) {
    return ["SwiftBar is not installed; skipping launch."];
  }
  try {
    execFileSync("osascript", ["-e", 'quit app "SwiftBar"'], { stdio: "ignore" });
  } catch {
    // SwiftBar may not be running yet.
  }
  try {
    execFileSync("open", [appPath], { stdio: "ignore" });
    execFileSync("sleep", ["1"], { stdio: "ignore" });
    return ["Opened SwiftBar.", ...clearSwiftBarStatusItemVisibility()];
  } catch (error) {
    return [`SwiftBar installed, but launch failed: ${error instanceof Error ? error.message : String(error)}`];
  }
}

function swiftBarEscape(value: string) {
  return value.replaceAll("|", "\\|");
}

function titleProviders(snapshot: StatusSnapshot) {
  return [...snapshot.providers].sort((left, right) => {
    const leftIndex = TITLE_PROVIDER_ORDER.indexOf(left.usage.provider);
    const rightIndex = TITLE_PROVIDER_ORDER.indexOf(right.usage.provider);
    const leftRank = leftIndex === -1 ? TITLE_PROVIDER_ORDER.length : leftIndex;
    const rightRank = rightIndex === -1 ? TITLE_PROVIDER_ORDER.length : rightIndex;
    return leftRank - rightRank;
  });
}

function titleSegment(provider: StatusSnapshot["providers"][number]) {
  const fiveHour = provider.analysis.fiveHour;
  const sevenDay = provider.analysis.sevenDay;
  const titleFive = fiveHour ? `${Math.round(fiveHour.usedPercent)}%` : "--";
  const titleSeven = sevenDay ? `${Math.round(sevenDay.usedPercent)}%` : "--";
  return `${formatProviderLabel(provider.usage.provider)}(${STATE_LABEL[provider.analysis.state]}) 5h ${titleFive} / 7d ${titleSeven}`;
}

function targetLabel(provider: StatusSnapshot["providers"][number]) {
  const target = provider.analysis.target;
  if (!target) {
    return "Target: learning";
  }
  return `Target: ${target.minPercent.toFixed(1)}%-${target.maxPercent.toFixed(1)}%`;
}

function windowByName(provider: StatusSnapshot["providers"][number], name: "five_hour" | "seven_day") {
  return provider.usage.windows.find((window) => window.name === name);
}

function row(label: string, value: string, color = TEXT_COLOR) {
  return `${label.padEnd(11)} ${value} | color=${color} font=${ROW_FONT} size=13`;
}

function muted(text: string) {
  return `${swiftBarEscape(text)} | color=${MUTED_COLOR} size=12`;
}

function issueLabel(code: string) {
  if (code === "CLAUDE_INGEST_MISSING") {
    return "Claude not connected";
  }
  if (code === "USAGE_STALE") {
    return "Usage data is stale";
  }
  if (code === "STATUS_MISSING") {
    return "Status not ready";
  }
  return code.replaceAll("_", " ").toLowerCase();
}

export function renderMenuBar(snapshot: StatusSnapshot = loadDisplayStatusSnapshot()) {
  const title = titleProviders(snapshot).map(titleSegment).join("  ");
  if (!title) {
    return ["No Usage", "---", "No provider usage available"].join("\n");
  }

  const lines = [title, "---"];

  for (const item of snapshot.providers) {
    const color = STATE_COLOR[item.analysis.state];
    const five = windowByName(item, "five_hour");
    const seven = windowByName(item, "seven_day");
    lines.push(`${formatProviderLabel(item.usage.provider)}  ${STATE_LABEL[item.analysis.state]} | color=${color} size=14`);
    if (five) {
      lines.push(row("5h usage", `${Math.round(five.usedPercent).toString().padStart(3)}%   reset ${formatDurationUntil(five.resetsAt)}`, color));
    }
    if (seven) {
      lines.push(row("7d usage", `${Math.round(seven.usedPercent).toString().padStart(3)}%   reset ${formatDurationUntil(seven.resetsAt)}`, TEXT_COLOR));
    }
    lines.push(muted(targetLabel(item)));
    lines.push(muted(item.analysis.message));
    lines.push("---");
  }

  for (const issue of snapshot.issues) {
    const color = ALERT_COLOR;
    lines.push(`${issue.severity.toUpperCase()}  ${issueLabel(issue.code)} | color=${color} size=13`);
    lines.push(muted(issue.message));
  }

  if (snapshot.issues.length > 0) {
    lines.push("---");
  }
  lines.push(muted(`Data age ${Math.max(0, ...snapshot.providers.map((item) => item.meta.ageSeconds))}s`));
  lines.push("Refresh now | refresh=true color=#111827");
  return lines.join("\n");
}

function pluginScript(paths: RuntimePaths) {
  return `#!${process.execPath}
// ${MARKER}
// <swiftbar.title>Burn AI</swiftbar.title>
// <swiftbar.version>v0.1.0</swiftbar.version>
// <swiftbar.author>Burn AI</swiftbar.author>
// <swiftbar.desc>Local Claude Code and Codex burn-rate monitor.</swiftbar.desc>
// <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
// <swiftbar.hideAbout>true</swiftbar.hideAbout>
// <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
// <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
// <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
// <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
const { spawnSync } = require("node:child_process");
spawnSync(${JSON.stringify(process.execPath)}, [${JSON.stringify(appCliPath(paths))}, "daemon", "--once"], {
  encoding: "utf8",
});
const result = spawnSync(${JSON.stringify(process.execPath)}, [${JSON.stringify(appCliPath(paths))}, "menubar", "render"], {
  encoding: "utf8",
});
if (result.error) {
  console.log("Burn ERR");
  console.log("---");
  console.log(result.error.message);
  process.exit(0);
}
if (result.status !== 0) {
  console.log("Burn ERR");
  console.log("---");
  console.log(result.stderr || result.stdout || "burn-ai menubar render failed");
  process.exit(0);
}
process.stdout.write(result.stdout);
`;
}

function isManagedPlugin(paths: RuntimePaths) {
  const plugin = swiftBarPluginPath(paths);
  try {
    return fs.readFileSync(plugin.file, "utf8").includes(MARKER);
  } catch {
    return false;
  }
}

export function swiftBarStatusItemVisibilityKeys(defaultsOutput: string) {
  return defaultsOutput
    .split("\n")
    .map((line) => line.match(/^\s*"?((?:NSStatusItem Visible)[^"=]*)"?\s*=/)?.[1]?.trim())
    .filter((key): key is string => Boolean(key));
}

function clearSwiftBarStatusItemVisibility(options: { dryRun?: boolean } = {}) {
  let keys: string[];
  try {
    keys = swiftBarStatusItemVisibilityKeys(execFileSync("defaults", ["read", "com.ameba.SwiftBar"], {
      encoding: "utf8",
    }));
  } catch {
    return [];
  }

  if (keys.length === 0) {
    return [];
  }

  if (options.dryRun) {
    return [`[dry-run] would clear SwiftBar hidden status item cache: ${keys.join(", ")}`];
  }

  for (const key of keys) {
    try {
      execFileSync("defaults", ["delete", "com.ameba.SwiftBar", key], { stdio: "ignore" });
    } catch {
      // Ignore races with SwiftBar rewriting or deleting the same key.
    }
  }
  return [`Cleared SwiftBar hidden status item cache: ${keys.join(", ")}`];
}

export function installMenuBar(options: { dryRun?: boolean } = {}) {
  const dryRun = options.dryRun ?? false;
  const paths = buildPaths();
  const plugin = swiftBarPluginPath(paths);
  if (dryRun) {
    return [
      `[dry-run] would write SwiftBar plugin: ${plugin.file}`,
      ...clearSwiftBarStatusItemVisibility({ dryRun }),
    ];
  }
  if (isFile(plugin.file) && !isManagedPlugin(paths)) {
    return [`SwiftBar plugin already exists and is not managed by burn-ai: ${plugin.file}`];
  }
  ensureDir(plugin.dir);
  fs.writeFileSync(plugin.file, pluginScript(paths), { mode: 0o755 });
  return [
    `Installed SwiftBar plugin: ${plugin.file}`,
    ...clearSwiftBarStatusItemVisibility(),
    "Open SwiftBar and set its plugin folder to the Burn AI plugin directory if it is not already configured.",
    `Plugin directory: ${plugin.dir}`,
  ];
}

export function uninstallMenuBar(options: { dryRun?: boolean } = {}) {
  const dryRun = options.dryRun ?? false;
  const paths = buildPaths();
  const plugin = swiftBarPluginPath(paths);
  if (!isFile(plugin.file)) {
    return ["No Burn AI SwiftBar plugin installed."];
  }
  if (!isManagedPlugin(paths)) {
    return [`SwiftBar plugin is user-managed; leaving it unchanged: ${plugin.file}`];
  }
  if (dryRun) {
    return [`[dry-run] would remove SwiftBar plugin: ${plugin.file}`];
  }
  fs.rmSync(plugin.file, { force: true });
  return [`Removed SwiftBar plugin: ${plugin.file}`];
}
