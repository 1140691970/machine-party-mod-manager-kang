import assert from "node:assert/strict";
import test from "node:test";
import {modAction} from "../../apps/desktop/ui/mod-action.js";

const copy = {managed:true, verified:true, cached:true, game:"Steam copy", scan:"ready", disk:"vanilla"};
test("an offline uninstall and restart retain the download and never offer adoption", () => {
  assert.equal(modAction({...copy, scan:"checking", local:"v1.7"}), "checking");
  assert.equal(modAction({...copy, disk:"installed", local:"v1.7"}), "uninstall");
  assert.equal(modAction({...copy, scan:"checking"}), "checking");
  assert.equal(modAction(copy), "install");
  for (const disk of ["restoreResidue", "needsRepair", "gameUpdatedOrModified", "identifyPending"])
    assert.equal(modAction({...copy, disk}), "review");
  assert.equal(modAction({...copy, disk:"manualInstall"}), "adoptManual");
});
test("a download is independent of verification and a failed scan blocks installation", () => {
  assert.equal(modAction({...copy, scan:"checking", cached:false}), "download");
  assert.equal(modAction({...copy, scan:"failed"}), "retryCheck");
  assert.equal(modAction({...copy, game:""}), "choose");
});
