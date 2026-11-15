import "date"
import "timezone"
option location = timezone.location(name: "America/Chicago")
selectedStart = date.truncate(t: v.timeRangeStart, unit: 1d)
stop = date.truncate(t: v.timeRangeStop, unit: 30s)
limitStart = date.truncate(t: date.sub(d: 30d, from: stop), unit: 1d)
start = if selectedStart < limitStart then limitStart else selectedStart
data = from(bucket: "home_history")
  |> range(start: start, stop: stop)
  |> filter(fn: (r) => r._measurement == "home_state" and r.domain == "sensor" and r.entity_id == "tcc_equipment_activity_code" and r._field == "value")
observed = data
  |> aggregateWindow(every: 30s, location: timezone.utc, fn: last, createEmpty: false)
  |> keep(columns: ["_time", "_value"])
missing = data
  |> aggregateWindow(every: 30s, location: timezone.utc, fn: count, createEmpty: true)
  |> filter(fn: (r) => r._value == 0)
  |> map(fn: (r) => ({_time: r._time, _value: -1.0}))
samples = union(tables: [observed, missing])
  |> filter(fn: (r) => r._time > start and r._time <= stop)
  |> group() |> sort(columns: ["_time"])
  |> duplicate(column: "_value", as: "delta")
  |> difference(columns: ["delta"], keepFirst: true)
  |> map(fn: (r) => ({
      _time: time(v: int(v: r._time) - 1), _start: start, _stop: stop,
      known: if exists r.delta and r.delta == 0.0 and (r._value == 0.0 or r._value == 1.0) then 0.5 else 0.0,
      heat: if exists r.delta and r.delta == 0.0 and r._value == 1.0 then 0.5 else 0.0
  }))
  |> group(columns: ["_start", "_stop"])
heat = samples |> map(fn: (r) => ({r with _value: r.heat}))
  |> aggregateWindow(every: 1d, fn: sum, timeSrc: "_start", createEmpty: false)
  |> keep(columns: ["_time", "_value"]) |> rename(columns: {_value: "heat"})
known = samples |> map(fn: (r) => ({r with _value: r.known}))
  |> aggregateWindow(every: 1d, fn: sum, timeSrc: "_start", createEmpty: false)
  |> keep(columns: ["_time", "_value"]) |> rename(columns: {_value: "known"})
unknown = samples |> map(fn: (r) => ({r with _value: 0.5 - r.known}))
  |> aggregateWindow(every: 1d, fn: sum, timeSrc: "_start", createEmpty: false)
  |> keep(columns: ["_time", "_value"]) |> rename(columns: {_value: "unknown"})
observedDaily = join(tables: {heat: heat, known: known}, on: ["_time"])
daily = join(tables: {observed: observedDaily, unknown: unknown}, on: ["_time"])
