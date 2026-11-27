import json, urllib.request
exec(open('/workspace/ogm-tests/vtest.py').read().split('cases = [')[0])
body={"model":"game-master","messages":[{"role":"system","content":sys_p},{"role":"user","content":"Zen picks up the scroll of Magic Missile from the altar."}],"tools":tools,"tool_choice":"auto","max_tokens":400,"temperature":0.7,"presence_penalty":0,"chat_template_kwargs":{"enable_thinking":True}}
r=json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8000/v1/chat/completions",json.dumps(body).encode(),{"Content-Type":"application/json"})))
print(json.dumps(r["choices"][0]["message"])[:800])
