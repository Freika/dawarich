# frozen_string_literal: true

require 'rails_helper'

# Labeled-scenario evaluation of the visit detection pipeline. Runs as part
# of the normal suite (and CI) so semantic regressions fail fast, and diffs
# the full detected timeline against a committed baseline so silent drift
# (boundary shifts, count changes) is caught even when the hard gates pass.
#
# Regenerate the baseline deliberately after a tuning change:
#   REGENERATE_VISITS_EVAL_BASELINE=1 bundle exec rspec spec/eval/visits_detection_eval_spec.rb
VISITS_EVAL_SCENARIOS = {
  home_gap: '2026-01-05 09:00',
  dark_dinner: '2026-01-06 17:00',
  drive_carving: '2026-01-07 12:00',
  reentry: '2026-01-08 10:00',
  cold_start: '2026-01-09 08:00',
  day_boundary: '2026-01-10 23:00',
  batch_boundary: '2026-01-31 23:00'
}.freeze

# Hard gates: what each scenario MUST produce, whatever the tuning.
VISITS_EVAL_GATES = {
  home_gap: { count: 1, min_duration_s: 4 * 3600 },
  dark_dinner: { count: 1 },
  drive_carving: { count: 0 },
  reentry: { count: 1, min_duration_s: 45 * 60, max_duration_s: 65 * 60 },
  cold_start: { count: 1 },
  day_boundary: { count: 1 },
  batch_boundary: { count: 1 }
}.freeze

VISITS_EVAL_TOLERANCE_S = 120

RSpec.describe 'Visit detection eval' do
  baseline_path = Rails.root.join('spec/eval/baselines/visits_rewrite_2026_08_09.json')

  def seed_scenario_data(user, scenario, index)
    now = Time.current
    rows = scenario[:points].map do |p|
      { user_id: user.id, timestamp: p[:timestamp],
        lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})",
        accuracy: p[:accuracy].round, velocity: p[:velocity].to_s,
        created_at: now, updated_at: now }
    end
    Point.insert_all(rows)

    track = create(:track, user: user)
    scenario[:segments].each_with_index do |s, i|
      create(:track_segment, track: track, transportation_mode: s[:mode],
                             confidence_score: s[:confidence_score],
                             start_index: (index * 1000) + (i * 11),
                             start_at: Time.zone.at(s[:start_ts]),
                             end_at: Time.zone.at(s[:end_ts]))
    end
  end

  def detected_timeline(user, origin_ts, window_start, window_end)
    created = Visits::Detection::Runner.new(user, start_at: window_start, end_at: window_end).call
    created.sort_by(&:started_at).map do |visit|
      {
        'start_offset' => visit.started_at.to_i - origin_ts,
        'end_offset' => visit.ended_at.to_i - origin_ts
      }
    end
  end

  it 'holds every scenario gate and matches the committed baseline timeline' do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
    report = {}

    VISITS_EVAL_SCENARIOS.each_with_index do |(name, start_time), index|
      user = create(:user)
      scenario = VisitScenarioGenerator.scenario(name, start_time: Time.zone.parse("#{start_time} UTC"),
                                                       seed: 42 + index)
      seed_scenario_data(user, scenario, index)

      origin_ts = scenario[:points].first[:timestamp]
      window_start = origin_ts - 1.hour.to_i
      window_end = scenario[:points].last[:timestamp] + 1.hour.to_i
      # batch_boundary must exercise the monthly batching + stitch path.
      window_end = window_start + 36.days.to_i if name == :batch_boundary

      visits = detected_timeline(user, origin_ts, window_start, window_end)
      report[name.to_s] = { 'count' => visits.size, 'visits' => visits }

      gate = VISITS_EVAL_GATES.fetch(name)
      expect(visits.size).to eq(gate[:count]), "#{name}: expected #{gate[:count]} visits, got #{visits.size}"

      durations = visits.map { |v| v['end_offset'] - v['start_offset'] }
      expect(durations.max.to_i).to be >= gate[:min_duration_s] if gate[:min_duration_s]
      expect(durations.max.to_i).to be <= gate[:max_duration_s] if gate[:max_duration_s]
    end

    File.write(Rails.root.join('tmp/visits_detection_eval_report.json'), JSON.pretty_generate(report))

    if ENV['REGENERATE_VISITS_EVAL_BASELINE']
      File.write(baseline_path, JSON.pretty_generate(report))
      skip 'baseline regenerated — commit the new file deliberately'
    end

    baseline = JSON.parse(File.read(baseline_path))
    report.each do |name, data|
      expected = baseline.fetch(name)
      expect(data['count']).to eq(expected['count']), "#{name}: count drifted from baseline"

      data['visits'].zip(expected['visits']).each do |actual, base|
        expect(actual['start_offset']).to be_within(VISITS_EVAL_TOLERANCE_S).of(base['start_offset']),
                                          "#{name}: visit start drifted beyond ±#{VISITS_EVAL_TOLERANCE_S}s"
        expect(actual['end_offset']).to be_within(VISITS_EVAL_TOLERANCE_S).of(base['end_offset']),
                                        "#{name}: visit end drifted beyond ±#{VISITS_EVAL_TOLERANCE_S}s"
      end
    end
  end

  it 'fails loudly when bridging is disabled — the harness catches semantic regressions' do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
    # Silence-bridging lives in TWO cooperating layers (fragment-level
    # GapBridger and the Runner's row-level stitcher) — a real regression
    # means losing both, so the probe disables both.
    allow_any_instance_of(Visits::Detection::GapBridger)
      .to receive(:call) { |_, fragments| fragments }
    allow_any_instance_of(Visits::Detection::Runner)
      .to receive(:stitch_adjacent) { |_, created| created }

    user = create(:user)
    scenario = VisitScenarioGenerator.scenario(:home_gap, start_time: Time.zone.parse('2026-02-01 09:00 UTC'))
    seed_scenario_data(user, scenario, 99)

    origin_ts = scenario[:points].first[:timestamp]
    visits = detected_timeline(user, origin_ts, origin_ts - 3600,
                               scenario[:points].last[:timestamp] + 3600)

    durations = visits.map { |v| v['end_offset'] - v['start_offset'] }
    expect(durations.max.to_i).to be < 4 * 3600 # the bridged 4h stay is gone — gate would fail
  end
end
