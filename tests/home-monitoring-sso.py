import json, runpy, sys, tempfile, zipfile
from pathlib import Path
source=(Path(__file__).resolve().parents[1] / 'modules/nixos/home-monitoring/configure_sso.py').read_text()
with tempfile.TemporaryDirectory() as directory:
 root=Path(directory);ha=root/'home-assistant';secrets=root/'secrets';ha.mkdir();secrets.mkdir();(ha/'.storage').mkdir()
 script=root/'configure.py';script.write_text(source.replace("Path('/var/lib/home-monitoring')",repr(root).replace('PosixPath','Path')))
 archive=root/'component.zip'
 with zipfile.ZipFile(archive,'w') as z:
  z.writestr('manifest.json',json.dumps({'version':'1.2.1'}))
 sys.argv=[str(script),str(archive)]
 def run():
  (ha/'configuration.yaml').write_text('default_config:\n')
  (secrets/'grafana.env').write_text('INFLUX_READ_TOKEN=test\n')
  try: runpy.run_path(str(script))
  except SystemExit as e: assert e.code==0
 def config(): return json.loads((ha/'oidc.yaml').read_text())
 run(); assert 'ENABLED=false' in (secrets/'grafana.env').read_text();assert 'auth_oidc:' not in (ha/'configuration.yaml').read_text()
 for name in ['home-assistant','grafana']:
  (secrets/(name+'-oidc.json')).write_text(json.dumps({'client_id':'test-id','client_secret':'test-secret'}))
 auth={'users':[{'id':'owner','is_owner':True}],'credentials':[{'user_id':'owner','auth_provider_type':'homeassistant','data':{'username':'ncwade'}}]}
 (ha/'.storage/auth').write_text(json.dumps({'data':auth}))
 run(); assert config()['features']['automatic_user_linking'];assert config()['roles']['user']=='home-monitoring-admin';assert 'test-secret' not in (ha/'configuration.yaml').read_text()
 auth['credentials'].append({'user_id':'owner','auth_provider_type':'auth_oidc','data':{'sub':'test-sub'}})
 (ha/'.storage/auth').write_text(json.dumps({'data':auth}))
 run();assert not config()['features']['automatic_user_linking']
 (secrets/'sso-disabled').touch();run();assert 'auth_oidc:' not in (ha/'configuration.yaml').read_text();assert 'ENABLED=false' in (secrets/'grafana.env').read_text()
 assert (ha/'.storage/auth').exists() and (secrets/'grafana-oidc.json').exists()
print('PASS: fresh onboarding, restricted initial linking, linking disabled after success, private secret references, recovery switch preserves accounts')
