import ast,copy,importlib.util,tempfile,unittest
from pathlib import Path
from .case_registry import cases

class UserCaseMatrix(unittest.TestCase):
 def test_all_requested_configs_preserve_model_values_and_native_modes(self):
  path=Path(__file__).resolve().parents[1]/'runner-src/scripts/runner.py'
  spec=importlib.util.spec_from_file_location('standalone_matrix',path);r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
  service={'host':'192.0.2.20','port':8000,'model':'test-model','tokenizer_path':'/mnt/weights/test'};r.CONFIG={'service':service}
  with tempfile.TemporaryDirectory() as temporary:
   r.BASE=Path(temporary)
   for case in cases(service):
    for output in ([102400,204800] if case['requested']['mode']=='accuracy' else [case['requested']['max_out_len']]):
     c=copy.deepcopy(case['requested']);c['max_out_len']=output;c['warmup']['max_out_len']=output
     with self.subTest(case=case['id'],output=output):
      self.assertEqual(r.validate(c),c['sample_limit'])
      text=r.make_config(c,r.BASE,Path('/data/performance.jsonl'));tree=ast.parse(text)
      values={n.targets[0].id:ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id in ('models','summarizer')}
      model=values['models'][0]
      for key in ('batch_size','max_out_len','retry','stream','generation_kwargs'):self.assertEqual(model[key],c[key])
      self.assertEqual(model['request_rate'],c['api']['request_rate'])
      self.assertIn('VLLMCustomAPIChat' if c['api']['endpoint']=='chat' else 'vllm_custom_api.VLLMCustomAPI',model['type'])
      if c['mode']=='performance':self.assertEqual('StablePerfMetricCalculator' in values['summarizer']['calculator']['type'],c['execution']['steady_state'])
