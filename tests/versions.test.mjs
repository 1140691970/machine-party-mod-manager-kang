import test from "node:test";
import assert from "node:assert/strict";
import { versionState } from "../ui/versions.js";
import { locales, messages, systemLocale } from "../ui/languages.js";

test("compares stable releases numerically and respects verification", () => {
  assert.equal(versionState("v1.9", "v1.10"), "waiting");
  assert.equal(versionState("v1.9", "v1.10", true), "available");
  assert.equal(versionState("2.1.0", "v2.1"), "same");
  assert.equal(versionState("v2.3", "v2.1", true), "newer");
  assert.equal(versionState("v2.1-beta", "v2.1", true), "review");
  assert.equal(versionState("1.7", undefined), "review");
  assert.equal(versionState(undefined, "v1.7"), "pending");
});
test("matches Chinese scripts and includes every translation", () => {
  assert.equal(systemLocale("zh-Hant-HK"), "zh-TW");
  assert.equal(systemLocale("zh-Hans"), "zh-CN");
  assert.equal(systemLocale("en-GB"), "en");
  for (const translations of Object.values(messages)) {
    assert.equal(translations.length, locales.length);
    assert.ok(translations.every(Boolean));
  }
});
