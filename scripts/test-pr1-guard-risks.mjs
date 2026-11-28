// Intended-behavior pins for PR #1 after dropping the inventory/coin narration
// guard port. Issue 1097 owns item/coin hand-offs (`item-claims*`); this suite
// asserts the guard no longer lists those kinds, that 1097's readerSystem
// contract still holds, and that deploy glue matches the offline qwen36 default.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { register } from "node:module";
import { suite } from "./lib/enforce-harness.mjs";

register("./lib/register-alias.mjs", import.meta.url);

const { CLAIM_KINDS, readerSystem } = await import("../src/lib/dm/claims-logic.ts");
const { duplicateAppliedProblem } = await import("../src/lib/dm/proposal-logic.ts");

const { test, finish } = suite("test-pr1-guard-risks");

await test("CLAIM_KINDS does not include item or coin (issue 1097 owns hand-offs)", () => {
  assert.ok(!CLAIM_KINDS.includes("item"));
  assert.ok(!CLAIM_KINDS.includes("coin"));
});

await test("readerSystem for stealth-only Ask does not list item or coin kinds", () => {
  const system = readerSystem(["stealth"], false);
  assert.ok(!system.includes('"kind":"item"'));
  assert.ok(!system.includes('"kind":"coin"'));
});

await test("duplicateAppliedProblem still blocks replayed auto-apply loot and coin", () => {
  const recent = [
    { kind: "grant_item", characterId: "c1", delta: { name: "Dagger", qty: 1 }, createdAt: new Date(Date.now() - 1_000).toISOString(), revertedAt: null },
    { kind: "modify_gold", characterId: "c1", delta: { copper: 30 }, createdAt: new Date(Date.now() - 1_000).toISOString(), revertedAt: null },
  ];
  assert.ok(duplicateAppliedProblem("grant_item", { item: "Rusty Dagger", srdName: "Dagger", qty: 1 }, { id: "c1", name: "Mira" }, recent, Date.now()));
  assert.ok(duplicateAppliedProblem("modify_gold", { coins: "+3 sp" }, { id: "c1", name: "Mira" }, recent, Date.now()));
  assert.equal(
    duplicateAppliedProblem("grant_item", { item: "Rusty Dagger", srdName: "Dagger", qty: 1, additional: true }, { id: "c1", name: "Mira" }, recent, Date.now()),
    null,
  );
});

await test("chat templates still forbid modify_gold for learn_spell / purchase", () => {
  for (const file of [
    "deploy/runpod/chat-templates/qwen36-ogm.jinja",
    "deploy/runpod/chat-templates/llama33-ogm.jinja",
    "deploy/runpod/chat-templates/qwen25-72b-ogm.jinja",
  ]) {
    const text = readFileSync(file, "utf8");
    assert.match(text, /never add modify_gold for a spell copy or a price/i, file);
  }
});

await test("install.sh does not download a model checkpoint", () => {
  const install = readFileSync("deploy/runpod/install.sh", "utf8");
  // Executable lines only: comments may still name historical rollback weights.
  const code = install.split("\n").filter((line) => !/^\s*#/.test(line)).join("\n");
  assert.doesNotMatch(code, /\bhf download\b/);
  assert.doesNotMatch(code, /Qwen2\.5-32B-Instruct-AWQ/);
  assert.doesNotMatch(code, /Qwen\/Qwen/);
  assert.match(install, /Qwen3\.6-35B-A3B-FP8/);
  assert.match(install, /HF_HUB_OFFLINE/);
});

await test("gm_model default and start_services agree on offline qwen36", () => {
  assert.equal(readFileSync("deploy/runpod/gm_model", "utf8").trim(), "qwen36");
  const start = readFileSync("deploy/runpod/start_services.sh", "utf8");
  assert.match(start, /echo qwen36/);
  assert.match(start, /HF_HUB_OFFLINE=1/);
  assert.match(start, /Qwen\/Qwen3\.6-35B-A3B-FP8/);
});

await test("1097 settle path remains after the engine boundary in turn.ts", () => {
  const turn = readFileSync("src/lib/dm/turn.ts", "utf8");
  const guardAt = turn.indexOf("await enforceEngineBoundary(");
  const settleAt = turn.indexOf("await settleItemClaims(");
  assert.ok(guardAt > 0 && settleAt > guardAt);
});

finish();
