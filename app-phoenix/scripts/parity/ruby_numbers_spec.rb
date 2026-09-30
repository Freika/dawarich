# frozen_string_literal: true

require 'rails_helper'

FLOAT_STRING_PROBES = [
  '12.3731', '-51.3402', '0', '0.0', '+5.5', '1e10', '1E-10', '1_000.5', '  12.5  ', '.5',
  '5.', '5', 'Infinity', '-Infinity', 'NaN', '0x1a', '0x1.8p3', '1_2_3.4_5', '123_', '_123',
  '1__2', '5,5', '5.5.5', '', '   ', 'abc', '5abc', '1e', '1e+', '1e1000', '-1e1000', '1e-1000',
  '٥.٥', '5٥', '0b101', '0o17', '1/2', '1 000', '5%', 'INFINITY', '+Infinity', '-0', '-0.0',
  '5.0e', '٫5', '5_', '_5', '5.5_', '5._5', '1.2.3', '+-5', '--5', '5+5', '5e5e5',
  '1.7976931348623157e308', '1.7976931348623157e309', '4.9e-324', '1e-400', 'true', 'null'
].freeze

RSpec.describe 'Phoenix fixture: Ruby float and Float() parity probes' do
  def postgis_build
    full = ActiveRecord::Base.connection.select_value('SELECT postgis_full_version()')
    postgis = full[/POSTGIS="([^"\s]+)/, 1]
    proj = full[/PROJ="([^"\s]+)/, 1]
    "POSTGIS=#{postgis} PROJ=#{proj}"
  end

  def leipzig_coord(rng, base, spread)
    (base + (rng.rand * spread)).round(6)
  end

  def edge_tie(rng, sign)
    integer_part = rng.rand(0..12_345)
    fraction = format('%05d', rng.rand(0..99_999))
    "#{sign}#{integer_part}.#{fraction}5".to_f
  end

  def sub_threshold(rng, sign)
    (sign * rng.rand * 0.0001).round(9)
  end

  # Deterministic across runs: a fixed seed, no wall-clock or process state.
  def build_floats
    rng = Random.new(20_260_928)
    floats = []
    124.times { floats << leipzig_coord(rng, 51.3, 0.1) }
    124.times { floats << -leipzig_coord(rng, 12.3, 0.15) }
    124.times { floats << edge_tie(rng, ['', '-'].sample(random: rng)) }
    124.times { floats << sub_threshold(rng, [1, -1].sample(random: rng)) }
    floats + [51.33971249996, 12_345.678925, 1.000005, 116.321965]
  end

  it 'records format, decimal-cast and to_s parity for a fixed set of floats and strings' do
    floats = build_floats
    expect(floats.size).to eq(500)
    expect(FLOAT_STRING_PROBES.size).to eq(60)

    column_type = Place.type_for_attribute('latitude')

    divergent_probe = 51.33971249996
    expect(BigDecimal(divergent_probe, 10).round(6)).not_to eq(column_type.cast(divergent_probe))

    float_rows = floats.map do |f|
      {
        'input' => f,
        'format_5f' => format('%.5f', f),
        'column_cast' => column_type.cast(f).to_s('F'),
        'round_5' => f.round(5),
        'to_s' => f.to_s
      }
    end

    # Recorded as text only: Rails' Oj-optimized JSON encoder re-rounds a
    # handful of these extreme-magnitude probes (Float::MAX, the smallest
    # denormal) to a mantissa some JSON parsers reject, so a raw numeric
    # field here would make the fixture unparseable rather than prove Ruby's
    # Float() behavior.
    string_rows = FLOAT_STRING_PROBES.map do |s|
      value = Float(s)
      { 'input' => s, 'ok' => true, 'to_s' => value.to_s }
    rescue ArgumentError, TypeError => e
      { 'input' => s, 'ok' => false, 'error_class' => e.class.name }
    end

    path = Rails.root.join('app-phoenix/test/fixtures/ruby_numbers.json')
    # An earlier, unrelated task already owns this exact filename for its own
    # "ruby"/"cases" keys (Dawarich.ReleaseMigrations.Effects.GeocodingRailsPinsTest
    # reads them). Preserve them untouched; only this task's own keys are added.
    legacy = File.exist?(path) ? JSON.parse(File.read(path)).slice('ruby', 'cases') : {}

    fixture = legacy.merge(
      'postgis_build' => postgis_build,
      'floats' => float_rows,
      'strings' => string_rows
    )

    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(fixture)}\n")
  end
end
