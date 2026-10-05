# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixture: jsonb float text written by ActiveRecord with Oj' do
  def hex(float)
    [float].pack('G').unpack1('H*')
  end

  def document_floats
    [1.0, 1000.0, 100_000.0, 1e15, 1e-7, 1e-5, -0.0, 0.1 + 0.2, 52.520008000000004, 0.1 + 0.7,
     1.0000000000000002, 1_234_567_890_123_456.7, 123_456_789.12345679, 4.35 * 100, 1e23, 9.87654321e-5,
     2.0**62, 5e-324, 1.5e300, 13.404954]
  end

  def named_floats
    document_floats + [
      -1.0, 100.0, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22, 9_007_199_254_740_994.0, 1e-4, 0.0001234,
      0.00001234, -1.5e300, -1.5, 0.0, 100.00000000000001, 2.0000000000000004, 0.1, 1 / 3.0, 2 / 3.0,
      12_345_678_901_234_567.0, -33.8688197, 1.1e-5, 1.005, 3.0000000000000004, -52.520008000000004, 0.5, 12.0,
      250.0, 123.456, -(2.0**62), 4_503_599_627_370_496.5, 0.000123456789012345678, -(2.0**63),
      Float::MAX, -Float::MAX, Float::MIN, Float::EPSILON, 51.480808220777476, 1100.0, 12_000.0, 2.0e6, 1500.0,
      8848.0, 1_234_567.0, 1.5e-300
    ]
  end

  def mantissa_floats
    mantissas = %w[1 1.5 2.5 7 9.99 1.23456 1.000001 4.940656 6.02214076]
    (-40..40).flat_map { |e| mantissas.map { |m| "#{m}e#{e}".to_f } }.each_with_index.map do |f, i|
      i.odd? ? -f : f
    end
  end

  def generated_floats(rng)
    floats = []
    300.times { floats << (51.3 + (rng.rand * 0.2)) }
    200.times { floats << -(12.3 + (rng.rand * 0.2)) }
    300.times { floats << (12.3 + (rng.rand * 0.2)).round(rng.rand(5..9)) }
    200.times { floats << ((rng.rand * 400).round(1) + (rng.rand * 400).round(1)) }
    200.times { floats << (rng.rand(1..90).to_f / rng.rand(1..900)) }
    200.times { floats << (rng.rand(0..2000) * 0.1) }
    100.times { floats << ((rng.rand - 0.5) * (10.0**rng.rand(-12..25))) }
    300.times { floats << (rng.rand(1..999_999).to_f / (10**rng.rand(0..12))) }
    200.times { floats << (rng.rand(1..999).to_f * (10**rng.rand(1..18))) }
    300.times { floats << rng.bytes(8).unpack1('G') }
    floats
  end

  def build_floats
    rng = Random.new(20_261_002)
    generated = generated_floats(rng)
    (named_floats + mantissa_floats + generated)
      .select(&:finite?)
      .reject { |f| hex(f) == hex(2.0**63) }
      .uniq { |f| hex(f) }
  end

  def value_text(type, float)
    json = type.serialize({ 'v' => float })
    raise "unexpected #{json}" unless json.start_with?('{"v":') && json.end_with?('}')

    json[5..-2]
  end

  def document_row(type, float)
    {
      'hex' => hex(float),
      'string_keys' => type.serialize({ 'v' => float }),
      'array' => type.serialize([float]),
      'nested' => type.serialize({ 'a' => { 'b' => [float, { 'c' => float }] } }),
      'symbol_keys' => type.serialize({ v: float })
    }
  end

  def write_fixture(fixture, rows)
    path = Rails.root.join('app-phoenix/test/fixtures/jsonb_floats.json')
    head = JSON.pretty_generate(fixture).delete_suffix("\n}")
    body = rows.map { |row| "    #{JSON.generate(row)}" }.join(",\n")
    FixtureRecording.verify(path, "#{head},\n  \"floats\": [\n#{body}\n  ]\n}\n")
  end

  it 'records the Rails jsonb text of floats, nested documents and non-finite values' do
    type = Point.type_for_attribute('raw_data')
    expect(type).to be_a(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb)

    floats = build_floats
    expect(floats.size).to be_between(2900, 3300)
    expect(document_floats.size).to eq(20)

    write_fixture(
      {
        'ruby' => RUBY_VERSION,
        'oj' => Oj::VERSION,
        'platform' => RUBY_PLATFORM,
        'serializer' => type.class.name,
        'non_finite' => [Float::NAN, Float::INFINITY, -Float::INFINITY].map { |f| type.serialize({ 'v' => f }) },
        'documents' => document_floats.map { |f| document_row(type, f) }
      },
      floats.map { |f| [hex(f), value_text(type, f)] }
    )
  end
end
