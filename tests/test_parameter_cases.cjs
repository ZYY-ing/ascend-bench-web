const assert=require('node:assert/strict');
const P=require('../runner-src/website/params.js');
const examples=[
 ['top_p=0.95,top_k=20',{top_p:.95,top_k:20}],
 ['top_p=0.95,top_k=20,repetition_penalty=1.05,frequency_penalty=0.2,presence_penalty=0.2',{top_p:.95,top_k:20,repetition_penalty:1.05,frequency_penalty:.2,presence_penalty:.2}],
 ['skip_special_tokens=true',{skip_special_tokens:true}],
 ['skip_special_tokens=false',{skip_special_tokens:false}],
 ['generation_kwargs.reasoning_effort="low"',{reasoning_effort:'low'}],
 ['chat_template_kwargs={"enable_thinking":false}',{chat_template_kwargs:{enable_thinking:false}}],
 ['top_p=0.95,top_k=20,seed=42,repetition_penalty=1.05,frequency_penalty=0.2,presence_penalty=0.2,skip_special_tokens=false',{top_p:.95,top_k:20,seed:42,repetition_penalty:1.05,frequency_penalty:.2,presence_penalty:.2,skip_special_tokens:false}]
];
for(const [raw,expected] of examples)assert.deepEqual(P.apply({},P.parse(raw)).generation_kwargs,expected);
assert.deepEqual(P.apply({},P.parse('request_rate=2,debug=false,max_num_workers=2')),{api:{request_rate:2},execution:{debug:false,max_num_workers:2}});
assert.throws(()=>P.parse('top_p=0.95,generation_kwargs.top_p=0.95'),/重复/);
assert.throws(()=>P.parse('generation_kwargs.mode="infer"'),/已有表单/);
console.log('User extra-parameter cases: models/API vs generation vs CLI mappings, false values, JSON objects, aliases and override rejection passed');
