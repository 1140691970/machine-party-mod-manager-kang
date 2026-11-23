import assert from "node:assert/strict";
import { access, readdir, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const languages = ["en", "zh-CN", "zh-TW"];
const labels = {"en": "English", "zh-CN": "简体中文", "zh-TW": "繁體中文"};
// English policies live at the repository root; translations live beside the guides.
const policies = ["CONTRIBUTING.md", "SECURITY.md", "SUPPORT.md", "CHANGELOG.md", "THIRD_PARTY_NOTICES.md"];
const skipped = new Set([".git", ".agent", ".cursor", ".codegraph", "node_modules", "target", "gen", "dist"]);

async function markdown(directory) {
  const found = [];
  for (const item of await readdir(path.join(root, directory), {withFileTypes: true})) {
    if (skipped.has(item.name)) continue;
    const relative = path.posix.join(directory, item.name);
    if (item.isDirectory()) found.push(...await markdown(relative));
    else if (item.name.endsWith(".md")) found.push(relative);
  }
  return found;
}

const guides = Object.fromEntries(await Promise.all(languages.map(async language => {
  const prefix = `docs/${language}/`;
  return [language, (await markdown(prefix.slice(0, -1))).map(file => file.slice(prefix.length)).sort()];
})));

test("every language has the same guides", () => {
  assert.deepEqual(guides["zh-CN"], guides["zh-TW"]);
  const extra = guides["zh-CN"].filter(file => !guides.en.includes(file));
  assert.deepEqual(extra.sort(), [...policies].sort());
  assert.deepEqual(guides.en.filter(file => !guides["zh-CN"].includes(file)), []);
});

test("translated policies exist at the root", async () => {
  for (const policy of policies) await access(path.join(root, policy));
});

test("all three README mod tables match the repository catalog", async () => {
  const catalog = JSON.parse(await readFile(path.join(root, "catalog/mods.json"), "utf8"));
  const expected = catalog.mods
    .filter(mod => mod.role !== "library")
    .toSorted((a, b) => a.order - b.order)
    .map(mod => {
    const url = "https://github.com/" + mod.repo;
    return [mod.repo === catalog.repo ? url + "/tree/main/mods/" + mod.id : url, mod.version];
  });
  for (const file of ["README.md", "docs/readme/README.zh-CN.md", "docs/readme/README.zh-TW.md"]) {
    const source = await readFile(path.join(root, file), "utf8");
    const rows = source.matchAll(/^\| \[[^\]]+\]\((https:\/\/github\.com\/[^)]+)\) \| `([^`]+)` \|/gm);
    assert.deepEqual(Array.from(rows, ([, url, version]) => [url, version]), expected, file);
  }
});

test("each guide links to its counterparts and marks its own language", async () => {
  for (const language of languages) {
    for (const file of guides[language]) {
      const source = await readFile(path.join(root, "docs", language, file), "utf8");
      const switcher = source.split("\n").find(line => line.includes(labels.en) && line.includes(labels["zh-CN"]));
      assert.ok(switcher, `docs/${language}/${file} has no language switcher`);
      assert.ok(switcher.includes(`**${labels[language]}**`), `docs/${language}/${file} does not mark ${language}`);
      for (const other of languages.filter(other => other !== language)) {
        const counterpart = other === "en" && policies.includes(file)
          ? path.posix.relative(path.posix.dirname(`docs/${language}/${file}`), file)
          : path.posix.relative(path.posix.dirname(`docs/${language}/${file}`), `docs/${other}/${file}`);
        assert.ok(switcher.includes(`](${counterpart})`), `docs/${language}/${file} should link ${counterpart}`);
      }
    }
  }
});

test("relative Markdown links and images resolve", async () => {
  const files = await markdown(".");
  const broken = [];
  for (const file of files) {
    const source = (await readFile(path.join(root, file), "utf8")).replace(/```[\s\S]*?```/g, "");
    for (const [, target] of source.matchAll(/!?\[[^\]]*\]\(([^)\s]+)\)/g)) {
      if (/^(?:[a-z]+:|#)/i.test(target)) continue;
      const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(file), decodeURI(target.split("#")[0])));
      try { await access(path.join(root, resolved)); }
      catch { broken.push(`${file} -> ${target}`); }
    }
  }
  assert.deepEqual(broken, []);
});
