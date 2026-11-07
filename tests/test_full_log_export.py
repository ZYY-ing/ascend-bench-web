import hashlib,importlib.util,json,tempfile,threading,unittest,urllib.request,urllib.error
from pathlib import Path

class FullLogExport(unittest.TestCase):
 def test_download_is_full_and_authenticated_while_poll_is_still_bounded(self):
  path=Path(__file__).resolve().parents[1]/'runner-src/scripts/runner.py'
  spec=importlib.util.spec_from_file_location('full_log_runner',path);r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
  with tempfile.TemporaryDirectory() as tmp:
   r.RUNS=Path(tmp);r.TOKEN='only-test-token';job=r.RUNS/'real-export-check';job.mkdir()
   (job/'record.json').write_text(json.dumps({'id':job.name,'status':'completed','log':'tail'}))
   raw=('FIRST-LINE-必须存在\n'+'long native log row\n'*30000+'LAST-LINE-完整😀\n').encode()
   (job/'execution.log').write_bytes(raw)
   class Handler(r.Handler):
    def log_message(self,*a):pass
   server=r.RunnerHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
   root='http://127.0.0.1:'+str(server.server_port);op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
   def get(path,auth=True):
    return op.open(urllib.request.Request(root+path,headers={'Cookie':'runner_session_'+str(server.server_port)+'=only-test-token'} if auth else {}),timeout=5)
   try:
    with get('/api/jobs/'+job.name) as response:poll=json.load(response)
    self.assertEqual(len(poll['log']),200000);self.assertNotIn('FIRST-LINE',poll['log'])
    with get('/api/jobs/'+job.name+'/log') as response:
     self.assertEqual(int(response.headers['Content-Length']),len(raw));download=response.read()
    self.assertEqual(hashlib.sha256(download).digest(),hashlib.sha256(raw).digest())
    self.assertTrue(download.startswith('FIRST-LINE'.encode()));self.assertTrue(download.endswith('完整😀\n'.encode()))
    with self.assertRaises(urllib.error.HTTPError) as error:get('/api/jobs/'+job.name+'/log',False)
    self.assertEqual(error.exception.code,401)
    with self.assertRaises(urllib.error.HTTPError) as error:get('/api/jobs/not-a-real-job/log')
    self.assertEqual(error.exception.code,404)
    (job/'record.json').write_text(json.dumps({'id':str(Path(tmp).parent),'status':'completed'}))
    with self.assertRaises(urllib.error.HTTPError) as error:get('/api/jobs/'+job.name+'/log')
    self.assertEqual(error.exception.code,404)
    self.assertEqual((job/'execution.log').read_bytes(),raw)
   finally:server.shutdown();server.server_close();thread.join(timeout=2)
