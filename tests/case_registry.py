"""User case registry. Requested and reduced live configurations stay separate."""
import copy

ACCURACY = [
 ('A01','GSM8K',0,1319,{}),('A05','GPQA',1.2,198,{}),('A09','AIME2026',2,30,{}),
 ('A10','GSM8K',1.2,16,{'top_p':.95,'top_k':20}),('A11','GPQA',1.2,16,{'top_p':.95,'top_k':20}),('A12','AIME2026',1.2,16,{'top_p':.95,'top_k':20}),
 ('A16','GPQA',1.2,16,{'top_p':.95,'top_k':20,'repetition_penalty':1.05,'frequency_penalty':.2,'presence_penalty':.2}),
 ('A17','GSM8K',1.2,16,{'skip_special_tokens':True}),('A18','GSM8K',1.2,16,{'skip_special_tokens':False}),
 ('A19','GPQA',1.2,16,{'reasoning_effort':'low'}),('A21','GPQA',1.2,16,{'chat_template_kwargs':{'enable_thinking':False}}),
 ('A22','GPQA',1.2,16,{}),('A24','GPQA',1.2,16,{}),('A25','GPQA',1.2,16,{}),('A26','GPQA',1.2,16,{}),('A27','GPQA',1.2,16,{})]
PERFORMANCE = [
 ('P01',16384,1,0,16,4,False,False),('P02',131072,1,0,12,3,False,False),('P03',131072,1,.9,64,16,False,False),
 ('P04',16384,1024,1,2240,450,True,False),('P05',131072,1024,1,2240,450,True,False),
 ('P07-16k',16384,1024,.9,1300,130,True,False),('P07-128k',131072,1024,.9,1300,130,True,False),
 ('P12',16384,1024,0,128,16,True,False),('P14',16384,1024,1,64,8,False,True),('P15',16384,1024,1,64,8,True,True),('P16',131072,1024,.9,64,8,True,True),
 ('P20',16384,1024,0,16,4,False,False),('P21',16384,1024,0,16,4,False,False),('P22',16384,1024,0,16,4,False,False),
 ('P23',131072,1024,.9,32,8,False,False),('P24',16384,1024,0,16,4,False,False),('P25',16384,1024,1,64,8,True,True)]

def cases(service):
 def base():
  return {'schema_version':3,'engine':'aisbench',**service,'max_out_len':102400,'batch_size':8,'generation_kwargs':{'temperature':0,'ignore_eos':False,'seed':42},'stream':False,'api':{'endpoint':'chat','request_rate':0,'trust_remote_code':False,'abbr':'standalone-eval'},'timeout':None,'retry':2,'sample_limit':16,'warmup':{'enabled':True,'count':8,'max_out_len':102400},'execution':{'mode':'all','steady_state':False,'pressure':False,'pressure_time':600,'debug':True,'max_num_workers':1,'dump_eval_details':True,'target':{'kind':'direct'}}}
 result=[]
 for ident,dataset,temp,count,extra in ACCURACY:
  c=base();c.update(mode='accuracy',dataset={'name':dataset},sample_limit=count);c['generation_kwargs'].update(temperature=temp,**extra)
  if ident=='A22':c['batch_size']=1
  if ident in ('A24','A25'):c['warmup'].update(count=0 if ident=='A24' else 16,enabled=ident!='A24')
  if ident=='A26':c['stream']=True
  if ident=='A27':c['api']['endpoint']='completions'
  result.append({'id':ident,'requested':c})
 for ident,inp,out,prefix,count,batch,steady,pressure in PERFORMANCE:
  c=base();c.update(mode='performance',max_out_len=out,batch_size=batch,sample_limit=count,stream=True,workload={'input_tokens':inp,'count':count,'prefix_ratio':prefix,'seed':20261107});c['generation_kwargs'].update(ignore_eos=True);c['warmup'].update(count=2 if prefix else 0,enabled=bool(prefix),max_out_len=out);c['execution'].update(mode='perf',steady_state=steady,pressure=pressure)
  if ident in ('P22','P25'):c['generation_kwargs'].update(temperature=1.2,top_p=.95,top_k=20)
  if ident=='P22':c['generation_kwargs'].update(repetition_penalty=1.05,frequency_penalty=.2,presence_penalty=.2,skip_special_tokens=False)
  if ident=='P23':c['generation_kwargs'].update(temperature=1.2,reasoning_effort='low')
  if ident=='P24':c['api']['request_rate']=2;c['execution'].update(debug=False,max_num_workers=2)
  result.append({'id':ident,'requested':c})
 return result
