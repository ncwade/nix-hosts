"""Run in the pinned HA image with a generated package targeting mobile_app_test_iphone.
Uses a fake notify action; no phone notification or home device action is performed.
"""
import asyncio,json
from pathlib import Path
from homeassistant.core import HomeAssistant, Context
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.script import Script

async def main():
    hass=HomeAssistant('/tmp/grafana-ha-test')
    automation=json.loads(Path('/config/packages/grafana_alerts.yaml').read_text())['automation'][0]
    calls=[]
    async def capture(call):calls.append(call.data)
    hass.services.async_register('notify','mobile_app_test_iphone',capture)
    script=Script(hass,cv.SCRIPT_SCHEMA(automation['actions']),'Grafana test','automation')
    payload={'alerts':[{'status':status,'labels':{'alertname':'Synthetic connector test'},'annotations':{'summary':'Synthetic failure'},'fingerprint':'test-only'} for status in ('firing','resolved')]}
    await script.async_run({'trigger':{'json':payload}}, context=Context())
    assert len(calls)==2,calls
    assert calls[0]['title']=='Alert: Synthetic connector test',calls[0]
    assert calls[1]['title']=='Recovered: Synthetic connector test',calls[1]
    assert 'cleared' in calls[1]['message'],calls[1]
    assert calls[0]['data']['tag']==calls[1]['data']['tag']
    await script.async_run({'trigger':{'json':{}}}, context=Context())
    assert len(calls)==2
    print('PASS: actual HA notification actions; firing/recovery text, grouping, empty payload')
    await hass.async_stop()
asyncio.run(main())
