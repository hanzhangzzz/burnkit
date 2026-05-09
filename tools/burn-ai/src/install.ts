import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { getClaudeStatusLineCommand, readClaudeSettings } from "./claude.js";
import { ensureConfig } from "./config.js";
import { ensureDir, isFile, writeJsonAtomic } from "./fs-util.js";
import { ensureSwiftBarInstalled, installMenuBar, openSwiftBar, uninstallMenuBar } from "./menubar.js";
import { buildPaths } from "./paths.js";
import { RuntimePaths } from "./types.js";

export const LAUNCHD_LABEL = "com.duying.burn-ai";
const MARKER = "burn-ai managed";

function appInstallDir(paths: RuntimePaths) {
  return path.join(paths.stateDir, "app");
}

function appCliPath(paths: RuntimePaths) {
  return path.join(appInstallDir(paths), "dist", "cli.js");
}

function currentPackageRoot() {
  const entry = fs.realpathSync(process.argv[1]);
  return path.resolve(path.dirname(entry), "..");
}

function installRuntimeApp(paths: RuntimePaths, dryRun: boolean) {
  const packageRoot = currentPackageRoot();
  const sourceDist = path.join(packageRoot, "dist");
  const sourceAssets = path.join(packageRoot, "assets");
  const target = appInstallDir(paths);
  const tmpTarget = path.join(paths.stateDir, `app.${process.pid}.tmp`);
  if (dryRun) {
    return [`[dry-run] would copy ${sourceDist} and ${sourceAssets} -> ${target}`];
  }
  if (path.resolve(packageRoot) === path.resolve(target)) {
    return [`Runtime app already installed: ${target}`];
  }
  if (!fs.existsSync(sourceDist)) {
    throw new Error(`Cannot install runtime app: missing built dist at ${sourceDist}`);
  }
  fs.rmSync(tmpTarget, { recursive: true, force: true });
  ensureDir(tmpTarget);
  fs.cpSync(sourceDist, path.join(tmpTarget, "dist"), { recursive: true });
  if (fs.existsSync(sourceAssets)) {
    fs.cpSync(sourceAssets, path.join(tmpTarget, "assets"), { recursive: true });
  }
  fs.copyFileSync(path.join(packageRoot, "package.json"), path.join(tmpTarget, "package.json"));
  fs.rmSync(target, { recursive: true, force: true });
  fs.renameSync(tmpTarget, target);
  return [`Installed runtime app: ${target}`];
}

function installedCliCommand(paths: RuntimePaths) {
  return [process.execPath, appCliPath(paths)];
}

function installedCliShimTarget(paths: RuntimePaths) {
  return appCliPath(paths);
}

function pathEntries() {
  return (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
}

function isManagedCliShim(paths: RuntimePaths) {
  try {
    return fs.lstatSync(paths.cliBinFile).isSymbolicLink()
      && path.resolve(path.dirname(paths.cliBinFile), fs.readlinkSync(paths.cliBinFile)) === installedCliShimTarget(paths);
  } catch {
    return false;
  }
}

function pathExists(file: string) {
  try {
    fs.lstatSync(file);
    return true;
  } catch {
    return false;
  }
}

function installCliShim(paths: RuntimePaths, dryRun: boolean) {
  const target = installedCliShimTarget(paths);
  const binInPath = pathEntries().includes(paths.cliBinDir);

  if (dryRun) {
    const pathMessage = binInPath
      ? `${paths.cliBinDir} is already in PATH`
      : `${paths.cliBinDir} is not in PATH; add it to use burn-ai directly`;
    return [`[dry-run] would link ${paths.cliBinFile} -> ${target}`, `[dry-run] ${pathMessage}`];
  }

  ensureDir(paths.cliBinDir);
  if (pathExists(paths.cliBinFile)) {
    if (isManagedCliShim(paths)) {
      fs.rmSync(paths.cliBinFile, { force: true });
    } else {
      return [`CLI shim already exists and is not managed by burn-ai: ${paths.cliBinFile}`];
    }
  }

  fs.symlinkSync(target, paths.cliBinFile);
  const messages = [`Installed CLI shim: ${paths.cliBinFile} -> ${target}`];
  if (!binInPath) {
    messages.push(`Add ${paths.cliBinDir} to PATH to use burn-ai directly.`);
  }
  return messages;
}

function plistXml(programArgs: string[]) {
  const args = programArgs
    .map((arg) => `        <string>${arg.replaceAll("&", "&amp;").replaceAll("<", "&lt;")}</string>`)
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCHD_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
${args}
        <string>daemon</string>
        <string>--once</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>StandardOutPath</key>
    <string>${path.join(os.homedir(), ".burn-ai", "daemon.log")}</string>
    <key>StandardErrorPath</key>
    <string>${path.join(os.homedir(), ".burn-ai", "daemon.err.log")}</string>
</dict>
</plist>
`;
}

function restartLaunchAgent(plistFile: string) {
  const domain = `gui/${process.getuid?.() ?? ""}`;
  try {
    execFileSync("launchctl", ["bootout", domain, plistFile], { stdio: "ignore" });
  } catch {
    // Not loaded yet or old launchctl behavior.
  }

  try {
    execFileSync("launchctl", ["bootstrap", domain, plistFile]);
    execFileSync("launchctl", ["kickstart", "-k", `${domain}/${LAUNCHD_LABEL}`]);
    return;
  } catch {
    // Fall back to the older interface used on older macOS versions.
  }

  try {
    execFileSync("launchctl", ["unload", plistFile], { stdio: "ignore" });
  } catch {
    // Not loaded yet.
  }
  execFileSync("launchctl", ["load", plistFile]);
}

function installClaudeStatusLine(paths: RuntimePaths, dryRun: boolean) {
  const settings = readClaudeSettings(paths.claudeSettingsFile);
  const existing = getClaudeStatusLineCommand(settings);
  const stableIngestCommand = `${process.execPath} ${appCliPath(paths)} ingest claude-statusline`;

  const existingScriptHasIngest =
    existing && fs.existsSync(existing)
      ? fs.readFileSync(existing, "utf8").includes("burn-ai ingest claude-statusline")
        || fs.readFileSync(existing, "utf8").includes(appCliPath(paths))
      : false;

  if (existing?.includes("burn-ai ingest claude-statusline") || existing?.includes(appCliPath(paths)) || existingScriptHasIngest) {
    return ["Claude status line already includes burn-ai ingest."];
  }

  if (existing) {
    return [
      "Claude status line already exists; burn-ai will not modify it.",
      "Add this near the top of your existing status line script:",
      '  input="$(cat)"',
      `  printf "%s" "$input" | ${stableIngestCommand} >/dev/null`,
      "Then make the rest of your script read from $input instead of stdin.",
    ];
  }

  const lines = [`# ${MARKER}`, 'input="$(cat)"', `printf "%s" "$input" | ${stableIngestCommand} >/dev/null`, 'printf "Burn AI ready"'];
  const script = `${lines.join("\n")}\n`;
  const newSettings = {
    ...(settings ?? {}),
    statusLine: {
      type: "command",
      command: paths.claudeStatusLineScript,
      padding: 0,
    },
  };

  if (dryRun) {
    return [
      `[dry-run] would create ${paths.claudeStatusLineScript}`,
      `[dry-run] would write statusLine.command to ${paths.claudeSettingsFile}`,
    ];
  }

  ensureDir(path.dirname(paths.claudeStatusLineScript));
  fs.writeFileSync(paths.claudeStatusLineScript, script, { mode: 0o755 });
  writeJsonAtomic(paths.claudeSettingsFile, newSettings);
  return [`Created Claude status line collector: ${paths.claudeStatusLineScript}`];
}

export function install(options: { dryRun?: boolean } = {}) {
  const dryRun = options.dryRun ?? false;
  const paths = buildPaths();
  const messages: string[] = [];

  if (process.platform !== "darwin") {
    messages.push("macOS launchd install is only implemented on macOS. Windows support is designed but not implemented in v1.");
    return messages;
  }

  if (!dryRun) {
    ensureDir(paths.stateDir);
    ensureDir(path.dirname(paths.launchAgentFile));
  }

  messages.push(...installRuntimeApp(paths, dryRun));
  messages.push(...installCliShim(paths, dryRun));
  if (dryRun) {
    messages.push(`[dry-run] would ensure config file: ${paths.configFile}`);
  } else if (ensureConfig(paths)) {
    messages.push(`Created config file: ${paths.configFile}`);
  }
  messages.push(...ensureSwiftBarInstalled({ dryRun }));
  messages.push(...installMenuBar({ dryRun }));
  if (!dryRun) {
    messages.push(...openSwiftBar());
  }
  messages.push(...installClaudeStatusLine(paths, dryRun));

  const args = installedCliCommand(paths);
  const xml = plistXml(args);
  if (dryRun) {
    messages.push(`[dry-run] would write launchd plist: ${paths.launchAgentFile}`);
    messages.push(`[dry-run] ProgramArguments: ${[...args, "daemon", "--once"].join(" ")}`);
    return messages;
  }

  fs.writeFileSync(paths.launchAgentFile, xml, "utf8");
  restartLaunchAgent(paths.launchAgentFile);
  messages.push(`Installed and restarted launchd agent: ${paths.launchAgentFile}`);
  return messages;
}

export function uninstall(options: { dryRun?: boolean } = {}) {
  const dryRun = options.dryRun ?? false;
  const paths = buildPaths();
  const messages: string[] = [];

  if (process.platform === "darwin" && isFile(paths.launchAgentFile)) {
    if (dryRun) {
      messages.push(`[dry-run] would unload and remove ${paths.launchAgentFile}`);
    } else {
      try {
        execFileSync("launchctl", ["unload", paths.launchAgentFile], { stdio: "ignore" });
      } catch {
        // Already unloaded.
      }
      fs.rmSync(paths.launchAgentFile, { force: true });
      messages.push(`Removed launchd agent: ${paths.launchAgentFile}`);
    }
  }

  if (isManagedCliShim(paths)) {
    if (dryRun) {
      messages.push(`[dry-run] would remove CLI shim ${paths.cliBinFile}`);
    } else {
      fs.rmSync(paths.cliBinFile, { force: true });
      messages.push(`Removed CLI shim: ${paths.cliBinFile}`);
    }
  } else if (isFile(paths.cliBinFile)) {
    messages.push(`CLI shim is user-managed; leaving it unchanged: ${paths.cliBinFile}`);
  }

  messages.push(...uninstallMenuBar({ dryRun }));

  const settings = readClaudeSettings(paths.claudeSettingsFile);
  const existing = getClaudeStatusLineCommand(settings);
  if (existing === paths.claudeStatusLineScript && settings) {
    if (dryRun) {
      messages.push(`[dry-run] would remove burn-ai statusLine from ${paths.claudeSettingsFile}`);
    } else {
      delete settings.statusLine;
      writeJsonAtomic(paths.claudeSettingsFile, settings);
      messages.push("Removed burn-ai managed Claude status line.");
    }
  } else if (existing) {
    messages.push("Claude status line is user-managed; leaving it unchanged.");
  }

  return messages.length ? messages : ["Nothing to uninstall."];
}
