// The catalog currently carries numeric upstream release tags. Treat other formats
// as unknown so a fork or prerelease never gets an automatic downgrade.
export function versionState(local, release, verified = false) {
  if (local === undefined) return verified ? "release" : "pending";
  const parse = value => typeof value === "string" && /^v?\d+(?:\.\d+)*$/i.test(value)
    ? value.replace(/^v/i, "").split(".").map(part => BigInt(part)) : null;
  const left = parse(local), right = parse(release);
  if (!left || !right) return "review";
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const a = left[i] ?? 0n, b = right[i] ?? 0n;
    if (a > b) return "newer";
    if (a < b) return verified ? "available" : "waiting";
  }
  return "same";
}
