import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { ensureDir, isFile } from "./fs-util.js";
import { formatDurationUntil, formatProviderLabel, formatWindowLabel } from "./format.js";
import { buildPaths } from "./paths.js";
import { loadDisplayStatusSnapshot } from "./runtime.js";
import { BurnState, RuntimePaths, StatusSnapshot } from "./types.js";

const MARKER = "burn-ai managed SwiftBar plugin";
const SWIFTBAR_APP_PATHS = ["/Applications/SwiftBar.app", path.join(process.env.HOME ?? "", "Applications", "SwiftBar.app")];

const STATE_LABEL: Record<BurnState, string> = {
  RAW: "WAIT",
  UNDER_BURN: "LOW",
  ON_TRACK: "OK",
  OVER_BURN: "FAST",
  LIMIT_RISK: "LIMIT",
};

const STATE_COLOR: Record<BurnState, string> = {
  RAW: "#6B7280",
  UNDER_BURN: "#B45309",
  ON_TRACK: "#15803D",
  OVER_BURN: "#B45309",
  LIMIT_RISK: "#B91C1C",
};

const TEXT_COLOR = "#111827";
const MUTED_COLOR = "#6B7280";
const ROW_FONT = "Menlo";

const STATE_WEIGHT: Record<BurnState, number> = {
  LIMIT_RISK: 5,
  UNDER_BURN: 4,
  OVER_BURN: 3,
  RAW: 2,
  ON_TRACK: 1,
};

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
    execFileSync("open", [appPath], { stdio: "ignore" });
    return ["Opened SwiftBar."];
  } catch (error) {
    return [`SwiftBar installed, but launch failed: ${error instanceof Error ? error.message : String(error)}`];
  }
}

function worstProvider(snapshot: StatusSnapshot) {
  return [...snapshot.providers].sort((left, right) => {
    return STATE_WEIGHT[right.analysis.state] - STATE_WEIGHT[left.analysis.state];
  })[0];
}

function swiftBarEscape(value: string) {
  return value.replaceAll("|", "\\|");
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
  return code.replaceAll("_", " ").toLowerCase();
}

export function renderMenuBar(snapshot: StatusSnapshot = loadDisplayStatusSnapshot()) {
  const provider = worstProvider(snapshot);
  if (!provider) {
    return ["Burn WAIT", "---", "No provider usage available"].join("\n");
  }

  const fiveHour = provider.analysis.fiveHour;
  const sevenDay = provider.analysis.sevenDay;
  const titleFive = fiveHour ? `${Math.round(fiveHour.usedPercent)}%` : "--";
  const titleSeven = sevenDay ? `${Math.round(sevenDay.usedPercent)}%` : "--";
  const title = `Burn ${STATE_LABEL[provider.analysis.state]} ${formatProviderLabel(provider.usage.provider)} 5h ${titleFive} / 7d ${titleSeven}`;
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
    const color = issue.severity === "error" ? "#B91C1C" : "#B45309";
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

export function installMenuBar(options: { dryRun?: boolean } = {}) {
  const dryRun = options.dryRun ?? false;
  const paths = buildPaths();
  const plugin = swiftBarPluginPath(paths);
  if (dryRun) {
    return [`[dry-run] would write SwiftBar plugin: ${plugin.file}`];
  }
  if (isFile(plugin.file) && !isManagedPlugin(paths)) {
    return [`SwiftBar plugin already exists and is not managed by burn-ai: ${plugin.file}`];
  }
  ensureDir(plugin.dir);
  fs.writeFileSync(plugin.file, pluginScript(paths), { mode: 0o755 });
  return [
    `Installed SwiftBar plugin: ${plugin.file}`,
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
