/**
 * recovery.ts — in-app recovery for the two brew failures users hit most and
 * previously could only fix from Terminal (issues #13/#102, #100).
 *
 * `classifyRecovery` is a PURE function of a failed {@link ActivityJob}: it
 * parses the brew command + stderr to decide whether a one-click retry with a
 * different flag would succeed, and which choices to offer. `runRecovery`
 * re-invokes the matching `api.ts` command with that flag, streaming into a
 * fresh Activity job like any other action.
 *
 * The whole point: a user whose install hit "It seems there is already an App
 * at…" or whose uninstall was "Refusing to uninstall … required by…" gets
 * Adopt / Overwrite / Force-remove buttons right on the failure card, instead
 * of being told to drop to a terminal.
 */

import { brewInstall, brewUninstall } from "$lib/api";
import type { ActivityJob, BrewStreamEvent, JobResult, PackageKind } from "$lib/types";

export type RecoveryKind = "adopt" | "overwrite" | "forceRemove";

export interface RecoveryChoice {
  kind: RecoveryKind;
  /** Button label. */
  label: string;
  /** Button styling — danger for overwrite/force, primary for the safe adopt. */
  variant: "primary" | "danger";
  /** One-line explanation shown under the buttons / as the button title. */
  hint: string;
}

export interface RecoveryOption {
  /** The command the original (failed) job ran. */
  action: "install" | "uninstall";
  name: string;
  kind: PackageKind;
  /** A short headline describing what went wrong, in plain language. */
  reason: string;
  /** Retry choices, in display order (safest first). */
  choices: RecoveryChoice[];
}

/** All log text of a job, joined for pattern-matching (stderr carries the
 *  brew error; stdout is included as a fallback for older brews). */
function jobText(job: ActivityJob): string {
  return job.lines.map((l) => l.text).join("\n");
}

/** Parse `[brew] <action> [--cask|--formula] <name> [flags…]` from a job's
 *  display command. Returns null when it isn't a recognizable install/uninstall
 *  (e.g. `brew upgrade`, `brew autoremove`, a tap update). */
function parseAction(
  command: string,
): { action: "install" | "uninstall"; name: string; kind: PackageKind } | null {
  const toks = command.trim().split(/\s+/);
  if (toks[0] === "brew") toks.shift();
  const action = toks[0];
  if (action !== "install" && action !== "uninstall") return null;
  const kind: PackageKind = toks.includes("--cask") ? "cask" : "formula";
  // The package name is the first token after the action that isn't a flag.
  const name = toks.slice(1).find((t) => !t.startsWith("-"));
  if (!name) return null;
  return { action, name, kind };
}

// brew's "already installed outside Homebrew" message. Matches casks ("App")
// and the rarer formula/binary variants, across brew versions.
const ALREADY_EXISTS = /it seems there is already an? (app|application|binary|file) at|already an app at/i;
// brew's dependency-protection refusal on uninstall.
const REQUIRED_BY = /refusing to uninstall|because it('s| is)? +(still +)?required by|is required by/i;

/**
 * Decide whether a failed job can be retried in-app, and how. Pure — safe to
 * call from a `$derived`. Returns null for anything not recoverable (success,
 * cancel, no exit code = our own spawn failure, or an unrecognized error).
 */
export function classifyRecovery(job: ActivityJob): RecoveryOption | null {
  // Only brew-ran-and-failed jobs are recoverable. No exit code = an IPC/spawn
  // failure (our bug) — that path keeps the "Report" button, not a retry.
  if (job.status !== "failed" || job.exitCode == null) return null;

  const parsed = parseAction(job.command);
  if (!parsed) return null;
  const text = jobText(job);

  if (parsed.action === "install" && ALREADY_EXISTS.test(text)) {
    const choices: RecoveryChoice[] = [];
    // --adopt only exists for casks; it's the safe, recommended fix.
    if (parsed.kind === "cask") {
      choices.push({
        kind: "adopt",
        label: "Adopt existing",
        variant: "primary",
        hint: "Let Homebrew manage the copy already on your Mac (keeps it in place).",
      });
    }
    choices.push({
      kind: "overwrite",
      label: "Overwrite",
      variant: "danger",
      hint: "Replace the existing copy with a fresh Homebrew install.",
    });
    return {
      ...parsed,
      reason: `${parsed.name} is already installed outside Homebrew.`,
      choices,
    };
  }

  if (parsed.action === "uninstall" && REQUIRED_BY.test(text)) {
    return {
      ...parsed,
      reason: `${parsed.name} is still required by another installed package.`,
      choices: [
        {
          kind: "forceRemove",
          label: "Force remove",
          variant: "danger",
          hint: "Remove it anyway, ignoring packages that depend on it.",
        },
      ],
    };
  }

  return null;
}

/**
 * Re-run the original command with the flag the chosen recovery implies.
 * Streams through `onEvent` exactly like the first attempt.
 */
export function runRecovery(
  opt: RecoveryOption,
  choice: RecoveryKind,
  onEvent: (evt: BrewStreamEvent) => void,
): Promise<JobResult> {
  switch (choice) {
    case "adopt":
      // brewInstall(name, kind, force, onEvent, adopt)
      return brewInstall(opt.name, opt.kind, false, onEvent, true);
    case "overwrite":
      return brewInstall(opt.name, opt.kind, true, onEvent, false);
    case "forceRemove":
      // brewUninstall(name, kind, zap, onEvent, ignoreDependencies)
      return brewUninstall(opt.name, opt.kind, false, onEvent, true);
  }
}

/** Human label for the Activity job a recovery spawns. */
export function recoveryJobLabel(opt: RecoveryOption, choice: RecoveryKind): string {
  switch (choice) {
    case "adopt":
      return `Adopting ${opt.name}`;
    case "overwrite":
      return `Reinstalling ${opt.name}`;
    case "forceRemove":
      return `Force-removing ${opt.name}`;
  }
}
