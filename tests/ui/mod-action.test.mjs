import assert from "node:assert/strict";
import test from "node:test";
import {installationProblem, modAction} from "../../apps/desktop/ui/mod-action.js";

const copy = {managed:true, verified:true, cached:true, game:"Steam copy", scan:"ready", disk:"vanilla"};
test("an offline uninstall and restart retain the download and never offer adoption", () => {
  assert.equal(modAction({...copy, scan:"checking", local:"v1.7"}), "checking");
  assert.equal(modAction({...copy, disk:"installed", local:"v1.7"}), "uninstall");
  assert.equal(modAction({...copy, scan:"checking"}), "checking");
  assert.equal(modAction(copy), "install");
  for (const disk of ["restoreResidue", "needsRepair", "gameUpdatedOrModified"])
    assert.equal(modAction({...copy, disk}), "review");
  assert.equal(modAction({...copy, disk:"identifyPending"}), "identify");
  assert.equal(modAction({...copy, disk:"manualInstall"}), "adoptManual");
});
test("cache availability never turns the install button into a download button", () => {
  assert.equal(modAction({...copy, cached:false}), "install");
  assert.equal(modAction({...copy, cached:true}), "install");
  assert.equal(modAction({...copy, scan:"checking"}), "checking");
  assert.equal(modAction({...copy, scan:"failed"}), "retryCheck");
  assert.equal(modAction({...copy, game:""}), "install");
});

test("installation succeeds only for the verified disk state and recorded release", () => {
  const mod = {id:"mod", repo:"author/mod", version:"v2"};
  const check = (disk, version) => installationProblem({modStates:{mod:disk}, installed:{[mod.repo]:version}}, mod);
  assert.equal(check("installed", "v2"), null);
  assert.equal(check("installed", "v1"), "statusUnavailable");
  assert.equal(check("vanilla", "v2"), "statusUnavailable");
  assert.equal(check("needsRepair", "v2"), "needsRepair");
  assert.equal(check("gameUpdatedOrModified", "v2"), "gameUpdatedOrModified");
});
