/**
 * Shared display formatters.
 *
 * `fmtBytes` was promoted verbatim from `Dashboard.svelte`'s component-local
 * copy so the Dashboard Storage card and the PackageDetail "Size" row
 * (Feature #4) render byte counts identically. The thresholds/precision are
 * the contract both shells honour: B (<1 KiB) / KB 1 decimal / MB 1 decimal /
 * GB 2 decimals. The native build's detail `human(_:)` mirrors the same table.
 */
export function fmtBytes(b: number): string {
  if (b < 1024) return `${b} B`;
  if (b < 1024 ** 2) return `${(b / 1024).toFixed(1)} KB`;
  if (b < 1024 ** 3) return `${(b / 1024 ** 2).toFixed(1)} MB`;
  return `${(b / 1024 ** 3).toFixed(2)} GB`;
}
