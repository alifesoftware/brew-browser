import { describe, it, expect } from "vitest";

import type { CategoriesData } from "$lib/types";
import { subgroupsFor, GENERAL_KEY, type Subgroup } from "./subcategories";

/**
 * Fixed fixture slice mirroring the shape of `categories.json`. Kept tiny and
 * deterministic so the parity assertion (Tauri vs native must produce identical
 * sub-group keys, labels, membership, and ordering) is reproducible on both
 * shells from the SAME input.
 *
 * dev-tools members (excluding casks):
 *   - "alpha"   formula  -> dev + security + data
 *   - "bravo"   formula  -> dev + security
 *   - "charlie" formula  -> dev + data
 *   - "delta"   formula  -> dev only            (solo -> general)
 *   - "echo"    formula  -> dev only            (solo -> general)
 *   - "foxtrot" cask     -> dev + security       (cask: excluded on Linux)
 */
function fixture(): CategoriesData {
  return {
    version: "test",
    generatedAt: "2026-06-12T00:00:00Z",
    model: "test",
    categories: {
      "developer-tools": { label: "Developer Tools", icon: "Wrench" },
      security: { label: "Security", icon: "Shield" },
      data: { label: "Data", icon: "Database" },
      uncategorized: { label: "Uncategorized", icon: "HelpCircle" },
    },
    formulae: {
      alpha: ["developer-tools", "security", "data"],
      bravo: ["developer-tools", "security"],
      charlie: ["developer-tools", "data"],
      delta: ["developer-tools"],
      echo: ["developer-tools"],
      // uncategorized members are all solo.
      uncat1: ["uncategorized"],
      uncat2: ["uncategorized"],
    },
    casks: {
      foxtrot: ["developer-tools", "security"],
    },
  };
}

/** Convenience: bucket items as plain name arrays, keyed by sub-group key. */
function byKey(groups: Subgroup[]): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const g of groups) out[g.key] = g.items.map((i) => i.name);
  return out;
}

describe("subgroupsFor — general bucket", () => {
  it("the general bucket size equals the count of solo members (macOS)", () => {
    const groups = subgroupsFor(fixture(), "developer-tools", false);
    const general = groups.find((g) => g.key === GENERAL_KEY)!;
    // delta + echo are dev-only (solo). alpha/bravo/charlie/foxtrot are cross-tagged.
    expect(general).toBeDefined();
    expect(general.items.map((i) => i.name)).toEqual(["delta", "echo"]);
    expect(general.label).toBe("General Developer Tools");
  });
});

describe("subgroupsFor — cross-tag membership", () => {
  it("a dev+security+data member appears in BOTH security and data, not general", () => {
    const groups = subgroupsFor(fixture(), "developer-tools", false);
    const map = byKey(groups);
    expect(map.security).toContain("alpha");
    expect(map.data).toContain("alpha");
    expect(map[GENERAL_KEY]).not.toContain("alpha");
  });

  it("no duplicate token within a single sub-group", () => {
    // Give a member a doubled co-category in its own array.
    const data = fixture();
    data.formulae.golf = ["developer-tools", "security", "security"];
    const groups = subgroupsFor(data, "developer-tools", false);
    const security = groups.find((g) => g.key === "security")!;
    const names = security.items.map((i) => i.name);
    expect(names.filter((n) => n === "golf")).toHaveLength(1);
  });
});

describe("subgroupsFor — ordering", () => {
  it("descending count, tie-break key slug, general pinned last", () => {
    const groups = subgroupsFor(fixture(), "developer-tools", false);
    // macOS counts: security={alpha,bravo,foxtrot}=3, data={alpha,charlie}=2,
    // general={delta,echo}=2. security(3) > data(2)==general(2); general pinned
    // last, so order is: security, data, general.
    expect(groups.map((g) => g.key)).toEqual(["security", "data", GENERAL_KEY]);
  });

  it("tie-break by key slug ascending when counts are equal", () => {
    // Two equal-count cross-tag buckets: data and security each have 1 member.
    const data: CategoriesData = {
      version: "t",
      generatedAt: "t",
      model: "t",
      categories: {
        x: { label: "X", icon: "I" },
        security: { label: "Security", icon: "I" },
        data: { label: "Data", icon: "I" },
      },
      formulae: {
        one: ["x", "security"],
        two: ["x", "data"],
      },
      casks: {},
    };
    const groups = subgroupsFor(data, "x", false);
    // counts equal (1 each), tie-break ascending: "data" < "security".
    expect(groups.map((g) => g.key)).toEqual(["data", "security"]);
  });
});

describe("subgroupsFor — Linux cask gate", () => {
  it("with excludeCasks=true, cask members are excluded from buckets and counts", () => {
    const macos = subgroupsFor(fixture(), "developer-tools", false);
    const linux = subgroupsFor(fixture(), "developer-tools", true);

    const macSecurity = macos.find((g) => g.key === "security")!;
    const linuxSecurity = linux.find((g) => g.key === "security")!;

    // foxtrot (cask) drops out on Linux; alpha + bravo remain.
    expect(macSecurity.items.map((i) => i.name)).toEqual(["alpha", "bravo", "foxtrot"]);
    expect(linuxSecurity.items.map((i) => i.name)).toEqual(["alpha", "bravo"]);
    // No cask name appears anywhere on Linux.
    const allLinuxNames = linux.flatMap((g) => g.items.map((i) => i.name));
    expect(allLinuxNames).not.toContain("foxtrot");
  });
});

describe("subgroupsFor — uncategorized is never a co-occurring bucket", () => {
  // Parity with native CategoryCatalog.subgroups(in:) — `uncategorized` is
  // sunk exactly as tiles()/allCategories sink it, so a member tagged
  // [X, uncategorized] is solo-in-X, not an "X + Uncategorized" bucket. Real
  // data has such tokens (translate-shell = [terminal, uncategorized]).
  function withMixed(): CategoriesData {
    const data = fixture();
    // dev + uncategorized only → must fold into general, NOT spawn a bucket.
    data.formulae.golf = ["developer-tools", "uncategorized"];
    return data;
  }

  it("a [selected + uncategorized]-only member lands in general, not a bucket", () => {
    const groups = subgroupsFor(withMixed(), "developer-tools", false);
    expect(groups.find((g) => g.key === "uncategorized")).toBeUndefined();
    const general = groups.find((g) => g.key === GENERAL_KEY)!;
    expect(general.items.map((i) => i.name)).toContain("golf");
  });

  it("selecting uncategorized splits members by their REAL co-occurring slug", () => {
    // Mirrors native uncategorizedSplitsByRealCoOccurrence: golf carries dev →
    // a "dev" bucket; a token carrying only uncategorized → general.
    const data = withMixed();
    data.formulae.solo = ["uncategorized"];
    const groups = subgroupsFor(data, "uncategorized", false);
    const map = byKey(groups);
    expect(map["developer-tools"]).toContain("golf"); // golf's real co-slug = dev
    expect(map[GENERAL_KEY]).toContain("solo"); // only-uncategorized → general
    expect(map[GENERAL_KEY]).not.toContain("golf"); // golf is not solo
  });
});

describe("subgroupsFor — degenerate all-solo category", () => {
  it("selecting 'uncategorized' (all-solo) produces exactly one bucket", () => {
    const groups = subgroupsFor(fixture(), "uncategorized", false);
    expect(groups).toHaveLength(1);
    expect(groups[0].key).toBe(GENERAL_KEY);
    expect(groups[0].items.map((i) => i.name)).toEqual(["uncat1", "uncat2"]);
    expect(groups[0].label).toBe("General Uncategorized");
  });
});

describe("subgroupsFor — set coverage", () => {
  it("sum of bucket sizes >= flat member count; union equals the flat set", () => {
    const groups = subgroupsFor(fixture(), "developer-tools", false);
    // Flat dev-tools members (macOS): alpha,bravo,charlie,delta,echo,foxtrot = 6.
    const flat = new Set(["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]);

    const sum = groups.reduce((acc, g) => acc + g.items.length, 0);
    expect(sum).toBeGreaterThanOrEqual(flat.size); // cross-tag duplicates inflate the sum

    const union = new Set(groups.flatMap((g) => g.items.map((i) => i.name)));
    expect(union).toEqual(flat);
  });

  it("returns empty for null data and for a slug with no members", () => {
    expect(subgroupsFor(null, "developer-tools", false)).toEqual([]);
    expect(subgroupsFor(fixture(), "no-such-slug", false)).toEqual([]);
  });
});

describe("subgroupsFor — parity fixture (Tauri vs native must match byte-for-byte)", () => {
  it("produces the exact ordered keys, labels, and membership for the fixed fixture", () => {
    const groups = subgroupsFor(fixture(), "developer-tools", false);
    // The native shell MUST reproduce this exact structure from the same input.
    expect(
      groups.map((g) => ({ key: g.key, label: g.label, items: g.items.map((i) => `${i.kind}:${i.name}`) })),
    ).toEqual([
      {
        key: "security",
        label: "Developer Tools + Security",
        items: ["formula:alpha", "formula:bravo", "cask:foxtrot"],
      },
      {
        key: "data",
        label: "Developer Tools + Data",
        items: ["formula:alpha", "formula:charlie"],
      },
      {
        key: GENERAL_KEY,
        label: "General Developer Tools",
        items: ["formula:delta", "formula:echo"],
      },
    ]);
  });
});
