import { describe, it, expect } from "vitest";

import type { ActivityJob, ActivityLine } from "$lib/types";
import { classifyRecovery } from "./recovery";

/** Build a failed ActivityJob with the given command + stderr lines. */
function failed(
  command: string,
  stderr: string[],
  extra: Partial<ActivityJob> = {},
): ActivityJob {
  const lines: ActivityLine[] = stderr.map((text) => ({
    stream: "stderr",
    text,
    ts: "2026-06-19T12:00:00.000Z",
  }));
  return {
    jobId: "j1",
    label: "x",
    command,
    startedAt: "2026-06-19T12:00:00.000Z",
    status: "failed",
    exitCode: 1,
    lines,
    ...extra,
  };
}

describe("classifyRecovery — install conflicts (#13/#102)", () => {
  it("offers Adopt + Overwrite for a cask that already exists", () => {
    const r = classifyRecovery(
      failed("brew install --cask google-chrome", [
        "Error: It seems there is already an App at '/Applications/Google Chrome.app'.",
      ]),
    );
    expect(r).not.toBeNull();
    expect(r!.action).toBe("install");
    expect(r!.kind).toBe("cask");
    expect(r!.name).toBe("google-chrome");
    expect(r!.choices.map((c) => c.kind)).toEqual(["adopt", "overwrite"]);
  });

  it("offers only Overwrite for a formula (no --adopt)", () => {
    const r = classifyRecovery(
      failed("brew install --formula foo", [
        "Error: It seems there is already a Binary at '/opt/homebrew/bin/foo'.",
      ]),
    );
    expect(r).not.toBeNull();
    expect(r!.kind).toBe("formula");
    expect(r!.choices.map((c) => c.kind)).toEqual(["overwrite"]);
  });
});

describe("classifyRecovery — uninstall dependency block (#100)", () => {
  it("offers Force remove when refused for a dependent", () => {
    const r = classifyRecovery(
      failed("brew uninstall --cask gstreamer-runtime", [
        "Error: Refusing to uninstall gstreamer-runtime",
        "because it is required by wine-stable, which is currently installed.",
      ]),
    );
    expect(r).not.toBeNull();
    expect(r!.action).toBe("uninstall");
    expect(r!.name).toBe("gstreamer-runtime");
    expect(r!.choices.map((c) => c.kind)).toEqual(["forceRemove"]);
  });
});

describe("classifyRecovery — non-recoverable cases", () => {
  it("returns null for a successful job", () => {
    expect(
      classifyRecovery(
        failed("brew install --cask x", ["whatever"], { status: "succeeded" }),
      ),
    ).toBeNull();
  });

  it("returns null when there is no exit code (our spawn failure)", () => {
    expect(
      classifyRecovery(failed("brew install --cask x", ["boom"], { exitCode: undefined })),
    ).toBeNull();
  });

  it("returns null for an unrelated brew upgrade failure", () => {
    expect(
      classifyRecovery(failed("brew upgrade", ["Error: some other failure"])),
    ).toBeNull();
  });

  it("returns null for an install failure that isn't an existing-app conflict", () => {
    expect(
      classifyRecovery(
        failed("brew install --cask x", ["Error: Download failed: 404"]),
      ),
    ).toBeNull();
  });
});
