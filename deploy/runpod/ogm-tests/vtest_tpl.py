import json, time, urllib.request, sys
URL = "http://127.0.0.1:8000/v1/chat/completions"
tools = [
 {"type":"function","function":{"name":"grant_item","description":"Give an item to a character. Required whenever a character gains an item.","parameters":{"type":"object","properties":{"character":{"type":"string"},"item":{"type":"string"},"quantity":{"type":"integer"}},"required":["character","item"]}}},
 {"type":"function","function":{"name":"modify_gold","description":"Add or remove gold pieces from a character.","parameters":{"type":"object","properties":{"character":{"type":"string"},"delta":{"type":"integer"}},"required":["character","delta"]}}},
 {"type":"function","function":{"name":"learn_spell","description":"Copy a spell into a wizard's spellbook; the engine charges 50 gp per spell level.","parameters":{"type":"object","properties":{"character":{"type":"string"},"spell":{"type":"string"},"level":{"type":"integer"}},"required":["character","spell","level"]}}},
]
sys_p = "You are the Game Master of a D&D 5e game. Game state only changes through tools: whenever a character gains or loses items or gold, or learns a spell, you MUST call the matching tool before narrating. Never narrate the player character's words or choices."
cases = [
 ("item", "Zen searches the dead bandit and pockets the potion of healing he finds."),
 ("item", "Zen picks up the scroll of Magic Missile from the altar."),
 ("item", "Zen takes the silver dagger from the display case and tucks it into his belt."),
 ("item", "Zen grabs the coil of rope and the lantern from the shelf."),
 ("item", "Zen pulls the ruby ring off the statue's finger."),
 ("gold", "Zen opens the chest and scoops up the 35 gold pieces inside."),
 ("spell", "Zen, a wizard, copies the Shield spell (level 1) from the scroll into his spellbook."),
]
want = {"item":"grant_item","gold":"modify_gold","spell":"learn_spell"}
mode = sys.argv[1] if len(sys.argv) > 1 else "ogm"
res = []
for kind, text in cases:
    body = {"model":"game-master","messages":[{"role":"system","content":sys_p},{"role":"user","content":text}],
            "tools":tools,"tool_choice":"auto","max_tokens":4096,"presence_penalty":0,
            "chat_template_kwargs":{"enable_thinking":True},"chat_template":open("/workspace/chat-templates/llama33-ogm.jinja").read()}
    if mode == "ogm":
        body["temperature"] = 0.7
    t = time.time()
    r = json.load(urllib.request.urlopen(urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type":"application/json"}), timeout=300))
    dt = time.time() - t
    m = r["choices"][0]["message"]
    calls = [c["function"]["name"] for c in (m.get("tool_calls") or [])]
    ok = want[kind] in calls
    res.append((kind, ok, round(dt,1), calls, len(m.get("reasoning") or m.get("reasoning_content") or ""), r["usage"]["completion_tokens"]))
for x in res: print(x)
print("hits", sum(1 for x in res if x[1]), "/", len(res), "avg_s", round(sum(x[2] for x in res)/len(res),1))
