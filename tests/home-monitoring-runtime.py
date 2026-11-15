#!/usr/bin/env python3
"""Read-only Flux integration tests. Run as root on Tycho; no telemetry is written."""
import csv
import datetime
import io
import json
from pathlib import Path
import re
from urllib.request import Request, urlopen

prefix = (Path(__file__).resolve().parents[1] / 'modules/nixos/home-monitoring/grafana/queries/daily-heating.flux').read_text()
token = Path('/var/lib/home-monitoring/secrets/grafana-read-token').read_text().strip()


def query(flux):
    request = Request('http://127.0.0.1:8086/api/v2/query?org=home',
                      data=json.dumps({'query': flux}).encode(),
                      headers={'Content-Type': 'application/json', 'Authorization': 'Token ' + token})
    with urlopen(request, timeout=60) as response:
        return list(csv.DictReader(line for line in io.StringIO(response.read().decode())
                                   if line.strip() and not line.startswith('#')))


def synthetic(start, seconds, states, expected):
    begin = datetime.datetime.fromisoformat(start)
    stop = (begin + datetime.timedelta(seconds=seconds)).isoformat()
    rows = ['{_time: time(v: "' + (begin + datetime.timedelta(seconds=i * 30 + 15)).isoformat()
            + '"), _value: ' + str(float(state)) + '}'
            for i, state in enumerate(states) if state is not None]
    flux = prefix.replace('import "date"', 'import "array"\nimport "date"')
    flux = re.sub(r'selectedStart = .*?\ndata =',
                  f'start = time(v: "{start}")\nstop = time(v: "{stop}")\ndata =', flux, flags=re.S)
    flux = re.sub(r'data = from\(bucket:.*?\nobserved = data',
                  'data = array.from(rows: [' + ', '.join(rows) + ']) |> range(start: start, stop: stop)\nobserved = data', flux, flags=re.S)
    result = query(flux + '\ndaily |> yield(name: "test")')
    assert len(result) == 1, 'Unexpected daily grouping'
    for field, value in expected.items():
        assert abs(float(result[0][field]) - value) < 0.001, (field, result[0][field], value)
    print('PASS:', start, seconds, 'seconds;', expected)
    return flux


synthetic('2026-03-08T06:00:00Z', 23 * 3600, [1] * (23 * 120),
          {'heat': 1379.5, 'known': 1379.5, 'unknown': 0.5})
fall = [1] * (25 * 120)
fall[10] = None
synthetic('2026-11-01T05:00:00Z', 25 * 3600, fall,
          {'heat': 1498.5, 'known': 1498.5, 'unknown': 1.5})
synthetic('2026-11-15T06:00:00Z', 240, [0, 0, 1, 1, 1, 0, -1, 0],
          {'heat': 1, 'known': 1.5, 'unknown': 2.5})
unknown = synthetic('2026-11-15T06:00:00Z', 240, [-1] * 8,
                    {'heat': 0, 'known': 0, 'unknown': 4})
assert not query(unknown + '\ndaily |> filter(fn: (r) => r.known > 0.0) |> yield(name: "test")')
print('PASS: all-unknown day omitted from heating totals, never shown as zero heating')
long = prefix.replace('v.timeRangeStart', 'date.sub(d: 365d, from: now())').replace('v.timeRangeStop', 'now()')
assert len(query(long + '\ndaily |> yield(name: "long-range")')) <= 32
print('PASS: long-range dashboard request bounds runtime computation to approximately one month')
