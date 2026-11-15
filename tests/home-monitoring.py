"""Execute inside the pinned HA image, with /config/packages/tcc.yaml available.
This uses synthetic HA states only; it never loads Honeywell or calls a service.
"""
import asyncio
import sys
from homeassistant.core import HomeAssistant
from homeassistant.helpers.template import Template
from homeassistant.util.yaml import load_yaml

async def main():
    hass = HomeAssistant('/tmp/tcc-template-test')
    sensors = {s['unique_id']: s for s in load_yaml(sys.argv[1] if len(sys.argv) > 1 else '/config/packages/tcc.yaml')['template'][0]['sensor']}
    def render(name, entity='climate.test', key='state'):
        return Template(sensors['tcc_'+name][key], hass).async_render({'tcc_entity':entity})
    assert render('equipment_activity_code', '') == -3
    assert render('availability', '') == 'not_discovered_or_ambiguous'
    hass.states.async_set('climate.test','heat',{'current_temperature':70,'temperature':72})
    assert render('equipment_activity_code') == -1, 'Heat mode must not become heating or idle'
    assert render('reported_hvac_action') == 'unknown_reading'
    assert render('heating_setpoint') == 72
    assert render('cooling_setpoint') is None
    assert render('indoor_temperature') == 70
    assert render('indoor_humidity') is None
    assert render('reported_fan_activity') == 'unknown_reading'
    hass.states.async_set('climate.test','heat',{'hvac_action':'heating', 'fan_action':'idle'})
    assert render('equipment_activity_code') == 1
    assert render('reported_fan_activity') == 'unknown_reading', 'Missing fan support must not become idle'
    hass.states.async_set('climate.test','heat_cool', {'target_temp_low':68, 'target_temp_high':76, 'hvac_action':'cooling'})
    assert render('equipment_activity_code') == 2
    assert render('heating_setpoint') == 68
    assert render('cooling_setpoint') == 76
    hass.states.async_set('climate.test','off',{'hvac_action':'off'})
    assert render('equipment_activity_code') == -1, 'Off mode does not prove equipment idle'
    hass.states.async_set('climate.test','heat',{'hvac_action':'idle','fan_modes':['auto','on'],'fan_mode':'auto','fan_action':'running'})
    assert render('equipment_activity_code') == 0
    assert render('reported_fan_activity') == 'running'
    assert render('fan_setting') == 'auto'
    hass.states.async_set('sensor.sitting_room_sitting_room_thermostat_outdoor_temperature','0',{'unit_of_measurement':'°C'})
    assert render('outdoor_temperature') == 32
    hass.states.async_set('sensor.sitting_room_sitting_room_thermostat_outdoor_temperature','22',{'unit_of_measurement':'°F'})
    assert render('outdoor_temperature') == 22
    hass.states.async_set('sensor.sitting_room_sitting_room_thermostat_outdoor_temperature','unknown')
    assert render('outdoor_temperature') is None
    hass.states.async_set('climate.test','unavailable')
    assert render('equipment_activity_code') == -2
    assert render('availability') == 'source_unavailable'
    assert render('indoor_temperature',key='availability') is False
    assert render('reported_hvac_action') == 'source_unavailable'
    print('PASS: missing capability, mode/action separation, setpoints, fan support, and unavailable handling')

asyncio.run(main())
