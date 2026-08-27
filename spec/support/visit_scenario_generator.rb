# frozen_string_literal: true

# Deterministic labeled scenarios for visit detection tests and eval.
# Each scenario returns raw points, transportation-style segments, and the
# ground truth (expected stays / untracked intervals) the pipeline must produce.
# Coordinates are around Leipzig; timestamps are epoch seconds.
module VisitScenarioGenerator
  HOME = { lat: 51.3402, lon: 12.3712 }.freeze
  METERS_PER_DEG_LAT = 111_320.0

  SCENARIOS = {
    home_gap: :build_home_gap,
    dark_dinner: :build_dark_dinner,
    drive_carving: :build_drive_carving,
    reentry: :build_reentry,
    cold_start: :build_cold_start,
    day_boundary: :build_day_boundary,
    batch_boundary: :build_batch_boundary,
    dark_venue: :build_dark_venue
  }.freeze

  module_function

  def scenario(name, start_time:, seed: 42)
    builder = SCENARIOS.fetch(name) { raise ArgumentError, "unknown scenario #{name.inspect}" }
    send(builder, Random.new(seed), start_time.to_i)
  end

  # -- scenario builders -------------------------------------------------

  # Fixes at home, 4 h of silence, fixes at home again, then a walk away.
  # Ground truth: ONE stay bridging the silence; nothing untracked.
  def build_home_gap(rng, start_ts)
    stay_a = stationary(rng, at: HOME, from_ts: start_ts, duration_s: 20 * 60)
    resume_ts = start_ts + (20 * 60) + (4 * 3600)
    stay_c = stationary(rng, at: HOME, from_ts: resume_ts, duration_s: 10 * 60)
    walk, = travel(rng, from: HOME, heading: 90.0, speed: 1.4,
                   from_ts: stay_c.last[:timestamp] + 30, duration_s: 10 * 60, dt_s: 30)

    {
      points: stay_a + stay_c + walk,
      segments: [
        segment('stationary', stay_a, 0.9),
        segment('walking', walk, 0.9)
      ],
      expected: {
        stays: [expected_stay(HOME, stay_a.first[:timestamp], stay_c.last[:timestamp])],
        untracked: []
      }
    }
  end

  # Fixes at a stop, 79 min of silence, fixes resume ~700 m away already driving.
  # Ground truth: the stop's stay, an untracked interval, and NO stay at resume.
  def build_dark_dinner(rng, start_ts)
    stop = offset(HOME, north_m: 300, east_m: 400)
    stay_a = stationary(rng, at: stop, from_ts: start_ts, duration_s: 20 * 60)
    gap_end_ts = stay_a.last[:timestamp] + (79 * 60)
    drive_start = offset(stop, north_m: -200, east_m: 680)
    drive, = travel(rng, from: drive_start, heading: 135.0, speed: 6.0,
                    from_ts: gap_end_ts, duration_s: 15 * 60, dt_s: 20)

    {
      points: stay_a + drive,
      segments: [
        segment('stationary', stay_a, 0.9),
        segment('driving', drive, 0.85)
      ],
      expected: {
        stays: [expected_stay(stop, stay_a.first[:timestamp], stay_a.last[:timestamp])],
        untracked: [{ start_ts: stay_a.last[:timestamp], end_ts: drive.first[:timestamp] }]
      }
    }
  end

  # Continuous slow city drive with five 2.5-minute traffic stops.
  # Ground truth: no stays, no untracked — it is all one drive.
  def build_drive_carving(rng, start_ts)
    points = []
    pos = offset(HOME, north_m: -500, east_m: -500)
    ts = start_ts

    5.times do
      leg, pos = travel(rng, from: pos, heading: 80.0, speed: 6.5,
                        from_ts: ts, duration_s: 5 * 60, dt_s: 20)
      points.concat(leg)
      ts = leg.last[:timestamp] + 30
      stop = stationary(rng, at: pos, from_ts: ts, duration_s: 150, dt_s: 30, jitter_m: 4)
      points.concat(stop)
      ts = stop.last[:timestamp] + 30
    end

    {
      points: points,
      segments: [segment('driving', points, 0.8)],
      expected: { stays: [], untracked: [] }
    }
  end

  # Café stay, 10-minute 300 m walk-away and back, café stay again.
  # Ground truth: ONE merged stay covering the whole span.
  def build_reentry(rng, start_ts)
    cafe = offset(HOME, north_m: 800, east_m: -200)
    stay_a = stationary(rng, at: cafe, from_ts: start_ts, duration_s: 20 * 60)
    away, apex = travel(rng, from: cafe, heading: 0.0, speed: 1.0,
                        from_ts: stay_a.last[:timestamp] + 30, duration_s: 5 * 60, dt_s: 30)
    back, = travel(rng, from: apex, heading: 180.0, speed: 1.0,
                   from_ts: away.last[:timestamp] + 30, duration_s: 5 * 60, dt_s: 30)
    stay_d = stationary(rng, at: cafe, from_ts: back.last[:timestamp] + 30, duration_s: 20 * 60)

    walk_points = away + back
    {
      points: stay_a + walk_points + stay_d,
      segments: [
        segment('stationary', stay_a, 0.9),
        segment('walking', walk_points, 0.85),
        segment('stationary', stay_d, 0.9)
      ],
      expected: {
        stays: [expected_stay(cafe, stay_a.first[:timestamp], stay_d.last[:timestamp])],
        untracked: []
      }
    }
  end

  # A drive ends; GPS goes dark for 8 minutes indoors; stationary fixes appear.
  # Ground truth: the stay STARTS at the driving segment's end (snapped), not at
  # the first indoor fix.
  def build_cold_start(rng, start_ts)
    drive, destination = travel(rng, from: offset(HOME, north_m: -900, east_m: 900),
                                heading: 350.0, speed: 10.0,
                                from_ts: start_ts, duration_s: 7 * 60, dt_s: 15)
    drive_end_ts = drive.last[:timestamp]
    indoor = stationary(rng, at: destination, from_ts: drive_end_ts + (8 * 60), duration_s: 25 * 60)

    {
      points: drive + indoor,
      segments: [segment('driving', drive, 0.9)],
      expected: {
        stays: [expected_stay(destination, drive_end_ts, indoor.last[:timestamp])],
        untracked: []
      }
    }
  end

  # One stay whose fixes cross midnight (caller passes an evening start_time).
  def build_day_boundary(rng, start_ts)
    spot = offset(HOME, north_m: 1200, east_m: 300)
    points = stationary(rng, at: spot, from_ts: start_ts, duration_s: (2.5 * 3600).to_i, dt_s: 300)

    {
      points: points,
      segments: [segment('stationary', points, 0.9)],
      expected: {
        stays: [expected_stay(spot, points.first[:timestamp], points.last[:timestamp])],
        untracked: []
      }
    }
  end

  # One stay whose fixes cross a detection batch edge (caller passes a
  # month-end start_time). Shape-wise a plain long stay; the Runner spec
  # asserts the batch stitcher yields exactly one visit.
  def build_batch_boundary(rng, start_ts)
    spot = offset(HOME, north_m: -1200, east_m: -700)
    points = stationary(rng, at: spot, from_ts: start_ts, duration_s: 2 * 3600, dt_s: 300)

    {
      points: points,
      segments: [segment('stationary', points, 0.9)],
      expected: {
        stays: [expected_stay(spot, points.first[:timestamp], points.last[:timestamp])],
        untracked: []
      }
    }
  end

  # -- primitives --------------------------------------------------------

  # One fix on arrival, 78 min of GPS-dark silence inside the venue, four
  # fixes reacquired on the way out with the departure walk already under
  # way — the walking segment starts between those fixes, so the stay's end
  # snaps ahead of most of its own evidence. Ground truth: ONE stay spanning
  # the silence; the edge fixes ARE the evidence and must keep counting.
  def build_dark_venue(rng, start_ts)
    venue = offset(HOME, north_m: 2200, east_m: -600)
    arrival = stationary(rng, at: venue, from_ts: start_ts, duration_s: 60, dt_s: 60)
    reacquire_ts = start_ts + (78 * 60)
    departure = stationary(rng, at: venue, from_ts: reacquire_ts, duration_s: 160, dt_s: 40)
    walk, = travel(rng, from: venue, heading: 210.0, speed: 1.4,
                   from_ts: reacquire_ts - 10, duration_s: 8 * 60, dt_s: 20)

    {
      points: (arrival + departure + walk).sort_by { |p| p[:timestamp] },
      segments: [segment('walking', walk, 0.9)],
      expected: {
        stays: [expected_stay(venue, start_ts, reacquire_ts - 10)],
        untracked: []
      }
    }
  end

  def stationary(rng, at:, from_ts:, duration_s:, dt_s: 60, jitter_m: 10, accuracy: 12.0)
    (duration_s / dt_s).times.map do |i|
      jitter_n = ((rng.rand * 2) - 1) * jitter_m
      jitter_e = ((rng.rand * 2) - 1) * jitter_m
      pos = offset(at, north_m: jitter_n, east_m: jitter_e)
      { lat: pos[:lat], lon: pos[:lon], timestamp: from_ts + (i * dt_s),
        accuracy: accuracy, velocity: (rng.rand * 0.2).round(2) }
    end
  end

  def travel(rng, from:, heading:, speed:, from_ts:, duration_s:, dt_s: 20, accuracy: 8.0)
    points = []
    pos = from
    (duration_s / dt_s).times do |i|
      v = [speed + (((rng.rand * 2) - 1) * speed * 0.15), 0.1].max
      dist = v * dt_s
      pos = offset(pos,
                   north_m: dist * Math.cos(heading * Math::PI / 180),
                   east_m: dist * Math.sin(heading * Math::PI / 180))
      points << { lat: pos[:lat], lon: pos[:lon], timestamp: from_ts + (i * dt_s),
                  accuracy: accuracy, velocity: v.round(2) }
    end
    [points, pos]
  end

  def offset(loc, north_m: 0, east_m: 0)
    lat = loc[:lat] + (north_m / METERS_PER_DEG_LAT)
    lon = loc[:lon] + (east_m / (METERS_PER_DEG_LAT * Math.cos(lat * Math::PI / 180)))
    { lat: lat.round(7), lon: lon.round(7) }
  end

  def segment(mode, points, confidence)
    { mode: mode, confidence_score: confidence, corrected: false,
      start_ts: points.first[:timestamp], end_ts: points.last[:timestamp] }
  end

  def expected_stay(loc, start_ts, end_ts)
    { lat: loc[:lat], lon: loc[:lon], start_ts: start_ts, end_ts: end_ts }
  end
end
