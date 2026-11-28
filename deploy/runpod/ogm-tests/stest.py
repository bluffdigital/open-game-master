import json, urllib.request
exec(open('/workspace/ogm-tests/vtest.py').read().split('cases = [')[0])
for text in ["Zen picks up the scroll of Magic Missile from the altar.","Zen collects the 120 gold pieces the quartermaster owes him."]:
    body={"model":"game-master","messages":[{"role":"system","content":sys_p},{"role":"user","content":text}],"tools":tools,"tool_choice":"auto","max_tokens":400,"temperature":0.7,"presence_penalty":0,"stream":True,"chat_template_kwargs":{"enable_thinking":True}}
    resp=urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8000/v1/chat/completions",json.dumps(body).encode(),{"Content-Type":"application/json"}))
    content="";calls=[]
    for line in resp:
        line=line.decode().strip()
        if not line.startswith("data:") or line.endswith("[DONE]"): continue
        d=json.loads(line[5:])
        if not d.get("choices"): continue
        dl=d["choices"][0].get("delta",{})
        content+=dl.get("content") or ""
        for tc in dl.get("tool_calls") or []:
            if tc.get("function",{}).get("name"): calls.append(tc["function"]["name"])
    print(calls, repr(content[:200]))
