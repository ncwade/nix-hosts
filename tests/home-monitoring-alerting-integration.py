"""Disposable local containers: real Grafana/InfluxDB with synthetic data only.
Requires Docker and the pinned images. Does not connect to Tycho.
"""
import importlib.util,json,os,pathlib,subprocess,tempfile,time,urllib.request,base64,threading,http.server,uuid,shutil
from unittest.mock import patch
repo=pathlib.Path(__file__).resolve().parents[1]
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
cfg=load('cfg',repo/'modules/nixos/home-monitoring/configure_alerting.py')
alerts=load('alerts',repo/'modules/nixos/bookorbit/alerts.py')
suffix=uuid.uuid4().hex[:8]; network='codex-alert-'+suffix; influx='influx-'+suffix; grafana='grafana-'+suffix
messages=[]
class Receiver(http.server.BaseHTTPRequestHandler):
 def do_POST(self):
  messages.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))));self.send_response(200);self.end_headers()
 def log_message(self,*args):pass
receiver=http.server.ThreadingHTTPServer(('0.0.0.0',0),Receiver)
threading.Thread(target=receiver.serve_forever,daemon=True).start()
def docker(*args):return subprocess.check_output(['docker',*args],text=True,stderr=subprocess.STDOUT).strip()
def api(base,path,data=None,auth=None,method=None):
 headers={'Content-Type':'application/json'}
 if auth:headers['Authorization']=auth
 body=json.dumps(data).encode() if data is not None else None
 with urllib.request.urlopen(urllib.request.Request(base+path,data=body,headers=headers,method=method),timeout=15) as r:
  raw=r.read();return json.loads(raw) if raw else None

def wait(fn,label,seconds=120):
 end=time.time()+seconds
 while time.time()<end:
  try:
   value=fn()
   if value:return value
  except Exception:pass
  time.sleep(2)
 raise AssertionError('Timed out: '+label)
try:
 docker('network','create',network)
 with tempfile.TemporaryDirectory(prefix='grafana-alert-check-') as tmp:
  root=pathlib.Path(tmp);root.chmod(0o755);(root/'secrets').mkdir();(root/'secrets/iphone-notify-service').write_text('notify.mobile_app_test_iphone')
  with patch.object(cfg.os,'chown'):cfg.configure(root)
  config=json.loads((root/'alerting/bookorbit.json').read_text());config['groups'][0]['interval']='10s'
  config['contactPoints'][0]['receivers'][0]['settings']['url']=f'http://host.docker.internal:{receiver.server_port}/'
  (root/'alerting/bookorbit.json').write_text(json.dumps(config));(root/'alerting/bookorbit.json').chmod(0o644);(root/'alerting').chmod(0o755)
  token='test-only-influx-token-12345678901234567890';(root/'token').write_text(token)
  (root/'datasources').mkdir();(root/'datasources/test.yaml').write_text(json.dumps({'apiVersion':1,'datasources':[{'name':'Home history','uid':'home-history','type':'influxdb','access':'proxy','url':f'http://{influx}:8086','jsonData':{'version':'Flux','organization':'home','defaultBucket':'home_history'},'secureJsonData':{'token':token}}]}))
  docker('run','-d','--name',influx,'--network',network,'-p','127.0.0.1::8086','influxdb:2.9.1@sha256:e4572d094ac3272f06528ea904ce6b4cb3bb19be2db3b3b1acbd27ba5c3a73e2')
  influx_url='http://'+docker('port',influx,'8086');wait(lambda:api(influx_url,'/health'),'InfluxDB startup')
  api(influx_url,'/api/v2/setup',{'username':'test','password':'test-password','org':'home','bucket':'home_history','token':token})
  # Use the actual Compose mount destinations, including the dashboard mounts.
  # Mounting a missing child beneath a read-only parent fails before Grafana starts.
  compose=(repo/'modules/nixos/home-monitoring/compose.yaml').read_text()
  volumes=compose.split('  grafana:',1)[1].split('    volumes:',1)[1].split('    healthcheck:',1)[0]
  shutil.copytree(repo/'modules/nixos/home-monitoring/grafana',root/'grafana')
  shutil.rmtree(root/'grafana/provisioning/datasources')
  shutil.copytree(root/'datasources',root/'grafana/provisioning/datasources')
  mounts=[]
  for line in volumes.splitlines():
   if ' - ' not in line:continue
   source,destination,*flags=line.strip().removeprefix('- ').split(':')
   if destination=='/var/lib/grafana':continue  # Disposable container storage.
   local=root/source.removeprefix('./') if source.startswith('./') else root/'alerting'
   mounts.extend(['-v',str(local)+':'+destination+(':'+':'.join(flags) if flags else '')])
  docker('run','-d','--name',grafana,'--network',network,'-p','127.0.0.1::3000','-e','GF_SECURITY_ADMIN_PASSWORD=test-password','-e','GF_UNIFIED_ALERTING_MIN_INTERVAL=10s','-e','GF_LOG_LEVEL=warn',*mounts,'grafana/grafana:13.3.1@sha256:0615ec4fbd4072004b7d86b46ded63013a74b7d6eb1119273dd89e8fa25c13cf')
  grafana_url='http://'+docker('port',grafana,'3000');auth='Basic '+base64.b64encode(b'admin:test-password').decode();wait(lambda:api(grafana_url,'/api/health'),'Grafana startup')
  rules=api(grafana_url,'/api/v1/provisioning/alert-rules',auth=auth);assert len(rules)==3
  assert all(r.get('notification_settings',{}).get('receiver')=='home-assistant-iphone' for r in rules),rules
  def states():
   data=api(grafana_url,'/api/prometheus/grafana/api/v1/rules',auth=auth)
   return {r['name']:r for group in data['data']['groups'] for r in group['rules']}
  wait(lambda: len(states())==3 and all(r['state']=='firing' and r.get('health') != 'error' for r in states().values()),'missing health alerts')
  print('PASS: all three missing health feeds alert',flush=True)
  def export(state):alerts.publish_health(state,root/'token',influx_url+'/api/v2/write?org=home&bucket=home_history&precision=s')
  export({})
  wait(lambda:all(r['state']=='inactive' for r in states().values()),'healthy samples resolve')
  print('PASS: healthy samples resolve all rules',flush=True)
  time.sleep(1);export({'incidents':{'kindle':{'since':time.time()}}})
  wait(lambda:states()['BookOrbit: Kindle import']['state']=='firing' and states()['BookOrbit: Audible downloads']['state']=='inactive','isolated connector failure')
  wait(lambda:any(a['status']=='firing' and a['labels'].get('connector')=='kindle' for m in messages for a in m.get('alerts',[])),'firing webhook')
  print('PASS: isolated failure is evaluated and delivered to webhook',flush=True)
  api(influx_url,'/api/v2/delete?org=home&bucket=home_history',{'start':'1970-01-01T00:00:00Z','stop':'2100-01-01T00:00:00Z','predicate':'_measurement="bookorbit_health"'},'Token '+token)
  time.sleep(1);export({})
  wait(lambda:all(r['state']=='inactive' for r in states().values()),'recovery evaluation')
  wait(lambda:any(a['status']=='resolved' and a['labels'].get('connector')=='kindle' for m in messages for a in m.get('alerts',[])),'resolved webhook')
  print('PASS: recovery notification delivered; production query window remains five minutes',flush=True)
finally:
 receiver.shutdown()
 for name in (grafana,influx):
  subprocess.run(['docker','rm','-f',name],capture_output=True)
 subprocess.run(['docker','network','rm',network],capture_output=True)
