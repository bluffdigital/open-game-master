import jinja2
e=jinja2.Environment(extensions=['jinja2.ext.loopcontrols'])
def rx(m): raise Exception(m)
t=e.from_string(open('/workspace/chat-templates/qwen25-72b-ogm.jinja').read())
tools=[{'type':'function','function':{'name':'grant_item','parameters':{}}}]
msgs=[{'role':'system','content':'You are GM.'},{'role':'user','content':'hi'},{'role':'assistant','content':None,'tool_calls':[{'id':'1','type':'function','function':{'name':'grant_item','arguments':'{"a":1}'}},{'id':'2','type':'function','function':{'name':'grant_item','arguments':'{"a":2}'}}]},{'role':'tool','tool_call_id':'1','content':'ok'},{'role':'user','content':'I take the sword'}]
print(t.render(messages=msgs,tools=tools,add_generation_prompt=True,bos_token='<s>',raise_exception=rx,enable_thinking=True)[-1000:])
print('---')
print(t.render(messages=[{'role':'system','content':'Reply with ONLY a JSON object'},{'role':'user','content':'q'}],add_generation_prompt=True,bos_token='<s>',raise_exception=rx)[-200:])
