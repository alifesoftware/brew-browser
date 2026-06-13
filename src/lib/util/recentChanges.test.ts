import { describe, it, expect } from "vitest";

import type { ActivityJob } from "$lib/types";
import {
  classify,
  recentChanges,
  changeVerb,
  normalizeStartedAt,
} from "./recentChanges";

/** Build a minimal terminal ActivityJob for feed tests. */
function job(
  partial: Partial<ActivityJob> & Pick<ActivityJob, "label" | "command">,
): ActivityJob {
  return {
    jobId: partial.jobId ?? crypto.randomUUID(),
    label: partial.label,
    command: partial.command,
    startedAt: partial.startedAt ?? "2026-06-09T12:00:00.000Z",
    status: partial.status ?? "succeeded",
    lines: partial.lines ?? [],
  };
}

describe("classify", () => {
  it("classifies a single install", () => {
    expect(classify("Installing wget", "brew install wget")).toEqual({
      kind: "installed",
      package: "wget",
      count: null,
    });
  });

  it("classifies a single uninstall", () => {
    expect(classify("Uninstalling wget", "brew uninstall wget")).toEqual({
      kind: "uninstalled",
      package: "wget",
      count: null,
    });
  });

  it("classifies a single upgrade", () => {
    expect(classify("Upgrading wget", "brew upgrade wget")).toEqual({
      kind: "upgraded",
      package: "wget",
      count: null,
    });
  });

  it("classifies a bulk upgrade with a count and no single name", () => {
    expect(classify("Upgrading 3 packages", "brew upgrade a b c")).toEqual({
      kind: "upgraded",
      package: null,
      count: 3,
    });
  });

  it("classifies 'Upgrading all packages' as bulk with no name or count", () => {
    expect(classify("Upgrading all packages", "brew upgrade")).toEqual({
      kind: "upgraded",
      package: null,
      count: null,
    });
  });

  it("excludes tap update (brew update) as 'other'", () => {
    expect(classify("Updating Homebrew taps", "brew update")).toEqual({
      kind: "other",
      package: null,
      count: null,
    });
  });

  it("excludes Brewfile dump as 'other'", () => {
    expect(classify("Dumping Brewfile: nightly", "brew bundle dump")).toEqual({
      kind: "other",
      package: null,
      count: null,
    });
  });

  it("ignores command-line flags — package read from the label", () => {
    expect(
      classify("Installing iterm2", "brew install iterm2 --force"),
    ).toEqual({ kind: "installed", package: "iterm2", count: null });
  });

  it("returns 'other' for an unknown label without crashing", () => {
    expect(classify("Frobnicating the foobar", "brew frob foobar")).toEqual({
      kind: "other",
      package: null,
      count: null,
    });
  });
});

describe("recentChanges", () => {
  it("returns [] for empty history (empty-state, no fabricated rows)", () => {
    expect(recentChanges([])).toEqual([]);
  });

  it("excludes running jobs", () => {
    const jobs = [
      job({ label: "Installing wget", command: "brew install wget", status: "running" }),
      job({ label: "Installing curl", command: "brew install curl", status: "succeeded" }),
    ];
    const out = recentChanges(jobs);
    expect(out.map((c) => c.package)).toEqual(["curl"]);
  });

  it("filters out 'other' (update/bundle) kinds from the package-change feed", () => {
    const jobs = [
      job({ label: "Updating Homebrew taps", command: "brew update" }),
      job({ label: "Dumping Brewfile: nightly", command: "brew bundle dump" }),
      job({ label: "Installing wget", command: "brew install wget" }),
    ];
    const out = recentChanges(jobs);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ kind: "installed", package: "wget" });
  });

  it("includes succeeded, failed, and canceled changes (status carried)", () => {
    const jobs = [
      job({ label: "Installing a", command: "brew install a", status: "succeeded" }),
      job({ label: "Installing b", command: "brew install b", status: "failed" }),
      job({ label: "Installing c", command: "brew install c", status: "canceled" }),
    ];
    const out = recentChanges(jobs);
    expect(out.map((c) => c.status)).toEqual(["succeeded", "failed", "canceled"]);
  });

  it("sorts most-recent-first by normalized timestamp", () => {
    const jobs = [
      job({ label: "Installing old", command: "brew install old", startedAt: "2026-06-01T00:00:00.000Z" }),
      job({ label: "Installing new", command: "brew install new", startedAt: "2026-06-09T00:00:00.000Z" }),
      job({ label: "Installing mid", command: "brew install mid", startedAt: "2026-06-05T00:00:00.000Z" }),
    ];
    const out = recentChanges(jobs);
    expect(out.map((c) => c.package)).toEqual(["new", "mid", "old"]);
  });

  it("normalizes mixed ISO + epoch-seconds timestamps for ordering", () => {
    // native shape: startedAt as epoch SECONDS (number). 2026-06-09T00:00:00Z
    // = 1780963200s. The ISO job below is one day earlier and must sort after.
    const jobs = [
      job({ label: "Installing iso", command: "brew install iso", startedAt: "2026-06-08T00:00:00.000Z" }),
      job({
        label: "Installing epoch",
        command: "brew install epoch",
        // cast: native persists a number; the contract accepts both.
        startedAt: 1780963200 as unknown as string,
      }),
    ];
    const out = recentChanges(jobs);
    expect(out.map((c) => c.package)).toEqual(["epoch", "iso"]);
  });

  it("keeps stable order for equal timestamps (newest-first input wins)", () => {
    const ts = "2026-06-09T00:00:00.000Z";
    const jobs = [
      job({ label: "Installing first", command: "brew install first", startedAt: ts }),
      job({ label: "Installing second", command: "brew install second", startedAt: ts }),
    ];
    const out = recentChanges(jobs);
    expect(out.map((c) => c.package)).toEqual(["first", "second"]);
  });

  it("carries a bulk upgrade as count-only with a null package", () => {
    const out = recentChanges([
      job({ label: "Upgrading 5 packages", command: "brew upgrade a b c d e" }),
    ]);
    expect(out[0]).toMatchObject({ kind: "upgraded", package: null, count: 5 });
  });

  it("respects the limit (default 6, overridable)", () => {
    const jobs = Array.from({ length: 10 }, (_, i) =>
      job({
        label: `Installing pkg${i}`,
        command: `brew install pkg${i}`,
        startedAt: new Date(Date.UTC(2026, 5, 1 + i)).toISOString(),
      }),
    );
    expect(recentChanges(jobs)).toHaveLength(6);
    expect(recentChanges(jobs, 3)).toHaveLength(3);
    expect(recentChanges(jobs, Infinity)).toHaveLength(10);
  });

  it("carries NO version field (no fabricated delta)", () => {
    const out = recentChanges([
      job({ label: "Upgrading wget", command: "brew upgrade wget" }),
    ]);
    expect(out[0]).not.toHaveProperty("version");
    expect(out[0]).not.toHaveProperty("oldVersion");
    expect(out[0]).not.toHaveProperty("newVersion");
  });
});

describe("changeVerb (parity with native ActivityView.displayLabel)", () => {
  it("maps kinds to the same past-tense verbs as native", () => {
    expect(changeVerb("installed")).toBe("Installed");
    expect(changeVerb("upgraded")).toBe("Upgraded");
    expect(changeVerb("uninstalled")).toBe("Uninstalled");
  });
});

describe("normalizeStartedAt", () => {
  it("parses an ISO string to epoch ms", () => {
    expect(normalizeStartedAt("1970-01-01T00:00:01.000Z")).toBe(1000);
  });

  it("converts epoch seconds (native) to ms", () => {
    expect(normalizeStartedAt(1)).toBe(1000);
  });

  it("returns 0 for an unparseable value (sorts to the end, never throws)", () => {
    expect(normalizeStartedAt("not-a-date")).toBe(0);
  });
});
