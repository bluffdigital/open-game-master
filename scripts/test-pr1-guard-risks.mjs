// Risk fixtures for PR #1's inventory/coin narration-guard port onto 0.40.2.
//
// The capture suites (test-item-proposals, test-engine-boundary) stay green for
// the happy paths they already pin. This file asserts the CORRECT ruling for
// the gaps the PR review named: faithful narration after learn_spell /
// party_award / handle_item / roll_treasure must not be treated as a
// contradiction. Each gap() documents a false rewrite that still fires today.
// A hard test() pins the issue-1097 readerSystem collision (CLAIM_KINDS now
// always lists item/coin in the shared claims system prompt).
import assert from "node:assert/strict";
import { register } from "node:module";
import { suite } from "./lib/enforce-harness.mjs";

register("./lib/register-alias.mjs", import.meta.url);

const {
  buildCorrectionPrompt,
  guardOutcomes,
  resolveOutcomes,
  ruleClaims,
  collectExchanges,
} = await import("../src/lib/dm/engine-boundary.ts");
const { readerSystem } = await import("../src/lib/dm/claims-logic.ts");
const { unrecordedItems } = await import("../src/lib/dm/item-claims-logic.ts");

const { test, gap, finish } = suite("test-pr1-guard-risks");

function conversationOf(calls) {
  const toolCalls = calls.map((call, index) => ({
    id: `call-${index}`,
    type: "function",
    function: { name: call.name, arguments: JSON.stringify(call.args ?? {}) },
  }));
  return [
    { role: "system", content: "system prompt" },
    { role: "user", content: "[Kara | attempt] I act." },
    { role: "assistant", content: "", tool_calls: toolCalls },
    ...calls.map((call, index) => ({
      role: "tool",
      tool_call_id: `call-${index}`,
      content: JSON.stringify(call.result ?? { ok: true }),
    })),
  ];
}

function rule(claims, calls) {
  return ruleClaims(claims, guardOutcomes(conversationOf(calls), null, "english"));
}

function outcomesOf(calls) {
  return resolveOutcomes(collectExchanges(conversationOf(calls)), null, "english");
}

const coinLoss = {
  kind: "coin",
  character: "Kara",
  characterId: "c1",
  amount: 50,
  denomination: "gp",
  direction: "loss",
  quote: "Kara spends fifty gold on inks",
};
const coinGain = {
  kind: "coin",
  character: "Kara",
  characterId: "c1",
  amount: 10,
  denomination: "gp",
  direction: "gain",
  quote: "Kara takes her share of ten gold",
};
const itemGain = {
  kind: "item",
  character: "Kara",
  characterId: "c1",
  item: "Lucky Coin",
  qty: 1,
  direction: "gain",
  quote: "Kara finds a lucky coin",
};
const itemLoss = {
  kind: "item",
  character: "Kara",
  characterId: "c1",
  item: "Rations",
  qty: 1,
  direction: "loss",
  quote: "Kara hands over a ration",
};

// ---- hard pins that must stay true on this branch ----

await test("deployed chat templates still forbid modify_gold for learn_spell / purchase", async () => {
  const { readFileSync } = await import("node:fs");
  for (const file of [
    "deploy/runpod/chat-templates/qwen36-ogm.jinja",
    "deploy/runpod/chat-templates/llama33-ogm.jinja",
    "deploy/runpod/chat-templates/qwen25-72b-ogm.jinja",
  ]) {
    const text = readFileSync(file, "utf8");
    assert.match(text, /never add modify_gold for a spell copy or a price/i, file);
  }
});

await test("grant_item / purchase items[] still feed outcomes via splitParts (not a false rewrite)", () => {
  const found = rule(
    [
      { kind: "item", character: "Kara", characterId: "c1", item: "Dagger", qty: 1, direction: "gain", quote: "Kara takes a dagger" },
      { kind: "item", character: "Kara", characterId: "c1", item: "Rope", qty: 1, direction: "gain", quote: "and a rope" },
    ],
    [
      {
        name: "grant_item",
        args: { characterId: "c1", items: [{ item: "Dagger", qty: 1 }, { item: "Rope", qty: 1 }] },
        result: { ok: true, granted: "Dagger" },
      },
    ],
  );
  assert.equal(found.length, 0);
  const bought = rule(
    [{ kind: "item", character: "Kara", characterId: "c1", item: "Torch", qty: 2, direction: "gain", quote: "Kara buys two torches" }],
    [
      {
        name: "purchase",
        args: { characterId: "c1", action: "buy", items: [{ item: "Torch", qty: 2 }] },
        result: { ok: true, bought: "Torch", paid: "2 cp" },
      },
    ],
  );
  assert.equal(bought.length, 0);
});

await test("turn order still runs enforceEngineBoundary before settleItemClaims", async () => {
  const { readFileSync } = await import("node:fs");
  const turn = readFileSync("src/lib/dm/turn.ts", "utf8");
  const guardAt = turn.indexOf("await enforceEngineBoundary(");
  const settleAt = turn.indexOf("await settleItemClaims(");
  assert.ok(guardAt > 0 && settleAt > guardAt, "guard rewrite can erase prose settle would auto-apply");
});

// ---- known false-rewrite / 1097-collision gaps (correct ruling; AssertionError = open) ----
// test-items-change-hands also hard-fails the readerSystem contract below.

const gapMeta = (rule, where) => ({
  rule,
  where,
  severity: "high",
  note: "PR #1 guard port vs 0.40.2 / issue 1097",
});

await gap(
  "reader-system-item-kind-collision",
  gapMeta(
    "item-claims reuses readerSystem and puts kind item only in the user message; CLAIM_KINDS must not list item/coin in the shared system prompt for a stealth-only Ask.",
    "src/lib/dm/claims-logic.ts CLAIM_KINDS / readerSystem",
  ),
  () => {
    assert.ok(!readerSystem(["stealth"], false).includes('"kind":"item"'));
    assert.ok(!readerSystem(["stealth"], false).includes('"kind":"coin"'));
  },
);

await gap(
  "learn_spell-gold-false-coin",
  gapMeta(
    "Faithful narration of learn_spell's in-tool gold spend must not be a coin contradiction (templates forbid modify_gold for the copy).",
    "src/lib/dm/engine-boundary.ts resolveOutcomes coins",
  ),
  () => {
    const calls = [
      {
        name: "learn_spell",
        args: { characterId: "c1", spell: "Shield", action: "add", from: "book" },
        result: {
          ok: true,
          learned: "Shield",
          spellbook: true,
          note: "Shield is written in the spellbook, for 50 gp and 2 hours of work. Kara can prepare it after a long rest.",
        },
      },
    ];
    assert.equal(outcomesOf(calls).coins.length, 0, "guard tracks no coin from learn_spell today");
    assert.deepEqual(rule([coinLoss], calls), [], "narrating the spend must not rewrite");
  },
);

await gap(
  "party-award-gold-false-coin",
  gapMeta(
    "Narration of gold after a successful party_award must match nested modify_gold the mutation layer already applied.",
    "src/lib/dm/engine-boundary.ts resolveOutcomes (party_award only appends a receipt)",
  ),
  () => {
    const calls = [
      {
        name: "party_award",
        args: { characterIds: ["c1", "c2"], xp: 50, gold: 20, reason: "hoard" },
        result: { ok: true, awarded: "50 XP each; 20 gold split 2 ways" },
      },
    ];
    assert.equal(outcomesOf(calls).coins.length, 0);
    assert.deepEqual(rule([coinGain], calls), []);
    // 1097 already accounts for party_award gold; guard must not fight it.
    assert.deepEqual(
      unrecordedItems(
        [{ kind: "item", character: "c1", name: "Kara", quote: coinGain.quote, said: false, change: "gains", item: "10 gp", copper: 1000 }],
        calls,
      ),
      [],
    );
  },
);

await gap(
  "party-award-item-false-item",
  gapMeta(
    "Narration of the finder receiving party_award's item must not be an item contradiction.",
    "src/lib/dm/engine-boundary.ts resolveOutcomes items",
  ),
  () => {
    const calls = [
      {
        name: "party_award",
        args: { characterIds: ["c1"], xp: 50, item: "Lucky Coin" },
        result: { ok: true, awarded: "50 XP each; Lucky Coin to Kara" },
      },
    ];
    assert.equal(outcomesOf(calls).items.length, 0);
    assert.deepEqual(rule([itemGain], calls), []);
    assert.deepEqual(
      unrecordedItems(
        [{ kind: "item", character: "c1", name: "Kara", quote: itemGain.quote, said: false, change: "gains", item: "Lucky Coin" }],
        calls,
      ),
      [],
    );
  },
);

await gap(
  "handle-item-false-item",
  gapMeta(
    "Narration after handle_item pick_up / hand must not be rewritten; 1097 already treats those calls as recorded moves.",
    "src/lib/dm/engine-boundary.ts resolveOutcomes items",
  ),
  () => {
    const pick = [
      {
        name: "handle_item",
        args: { characterId: "c1", action: "pick_up", item: "Lucky Coin" },
        result: { ok: true, applied: "Kara picks up Lucky Coin" },
      },
    ];
    const hand = [
      {
        name: "handle_item",
        args: { characterId: "c1", action: "hand", item: "Rations", toCharacterId: "c2" },
        result: { ok: true, applied: "handed" },
      },
    ];
    assert.equal(outcomesOf(pick).items.length, 0);
    assert.equal(outcomesOf(hand).items.length, 0);
    assert.deepEqual(rule([itemGain], pick), []);
    assert.deepEqual(rule([itemLoss], hand), []);
  },
);

await gap(
  "roll-treasure-false-coin",
  gapMeta(
    "Narration of party gold after roll_treasure must not be a coin contradiction; 1097 treats the roll as recorded money in.",
    "src/lib/dm/engine-boundary.ts resolveOutcomes coins",
  ),
  () => {
    const calls = [
      {
        name: "roll_treasure",
        args: { cr: 2 },
        result: { ok: true, gold: 80, perCharacter: 40, note: "split among the party" },
      },
    ];
    const treasureGain = { ...coinGain, amount: 40, quote: "Kara pockets forty gold from the hoard" };
    assert.equal(outcomesOf(calls).coins.length, 0);
    assert.deepEqual(rule([treasureGain], calls), []);
    assert.deepEqual(
      unrecordedItems(
        [{ kind: "item", character: "c1", name: "Kara", quote: treasureGain.quote, said: false, change: "gains", item: "40 gp", copper: 4000 }],
        calls,
      ),
      [],
    );
  },
);

await gap(
  "false-rewrite-correction-cites-empty-receipts",
  gapMeta(
    "A false coin contradiction after party_award must not ask for a rewrite that cites only a generic success receipt with no coin outcome.",
    "src/lib/dm/engine-boundary.ts buildCorrectionPrompt / toolReceipts",
  ),
  () => {
    const calls = [
      {
        name: "party_award",
        args: { characterIds: ["c1"], xp: 50, gold: 10, reason: "purse" },
        result: { ok: true, awarded: "50 XP each; 10 gold split 1 ways" },
      },
    ];
    const found = rule([coinGain], calls);
    assert.equal(found.length, 0, "no contradiction to correct");
    const prompt = buildCorrectionPrompt(found, outcomesOf(calls).toolReceipts);
    assert.doesNotMatch(prompt, /party_award SUCCEEDED/);
  },
);

finish();
