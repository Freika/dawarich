# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixture: lexical edges of Oj.load in compat mode, as Imports::FileLoader reads JSON' do
  let(:path) { Rails.root.join('app-phoenix/test/fixtures/imports/geojson/compat-lexical.json') }
  let(:backslash) { '\\' }

  let(:collector) do
    Class.new(Oj::Saj) do
      attr_reader :values

      def initialize
        super
        @values = []
      end

      def hash_start(_key) = nil
      def hash_end(_key) = nil
      def array_start(_key) = nil
      def array_end(_key) = nil
      def add_value(value, _key) = @values << value
      def error(message, _line, _column) = raise(Oj::ParseError, message)
    end
  end

  let(:cases) do
    {
      'prefix_block' => '/* root */{"altitude":1}',
      'prefix_line' => "// root\n{\"altitude\":1}",
      'suffix_block' => '{"altitude":1}/* end */',
      'suffix_line' => '{"altitude":1}// end',
      'inner_block' => '{"altitude":/* value */1}',
      'inner_line' => "{\"altitude\":// value\n1}",
      'exponent_missing' => '{"altitude":1e}',
      'exponent_sign' => '{"altitude":1e+}',
      'exponent_bad' => '{"altitude":1eX}',
      'dot_missing' => '{"altitude":1.}',
      'dot_exp' => '{"altitude":1.e2}',
      'leading_zero' => '{"altitude":01}',
      'leading_plus' => '{"altitude":+1}',
      'empty' => '',
      'two_docs' => '{} {}',
      'whitespace_end' => "{\"altitude\":1}\n \t"
    }.merge(review_cases)
  end

  def review_cases
    {
      'raw_tab' => "{\"altitude\":\"x\ty\"}", 'raw_soh' => "{\"altitude\":\"x\x01y\"}",
      'raw_lf' => "{\"altitude\":\"x\ny\"}", 'raw_del' => "{\"altitude\":\"x\x7Fy\"}",
      'raw_nul' => "{\"altitude\":\"x\x00y\"}",
      'escape_unknown_x' => "{\"altitude\":\"#{backslash}x\"}",
      'escape_unknown_q' => "{\"altitude\":\"a#{backslash}qb\"}",
      'escape_nul' => "{\"altitude\":\"a#{backslash}u0000b\"}",
      'escape_lone_low' => "{\"altitude\":\"#{backslash}uDC00\"}",
      'negative_leading_zero' => '{"altitude":-01}', 'negative_alone' => '{"altitude":-}',
      'negative_zero' => '{"altitude":-0}', 'negative_dot' => '{"altitude":-.5}',
      'double_zero' => '{"altitude":00}', 'negative_double_zero' => '{"altitude":-00}',
      'double_zero_fraction' => '{"altitude":00.5}', 'negative_zero_float' => '{"altitude":-0.0}',
      'negative_exponent' => '{"altitude":-1e2}', 'zero_exponent' => '{"altitude":0e1}'
    }
  end

  def outcome(name, raw)
    { name: name, input: raw, outcome: 'ok', value: Oj.load(raw, mode: :compat) }
  rescue StandardError => e
    { name: name, input: raw, outcome: 'error', error: e.class.name, message: e.message }
  end

  def valid?(raw)
    Oj::Parser.new(:validate).parse(raw)
    true
  rescue StandardError
    false
  end

  def portable(value)
    return value unless value.is_a?(String) && !value.valid_encoding?

    { '__bytes__' => value.unpack1('H*'), 'scrubbed' => value.scrub }
  end

  def saj(raw)
    handler = collector.new
    valid?(raw) ? Oj::Parser.new(:saj, handler:).parse(raw) : Oj.saj_parse(handler, raw)
    { outcome: 'ok', values: handler.values.map { |value| portable(value) } }
  rescue StandardError => e
    { outcome: 'error', error: e.class.name }
  end

  it 'records every case' do
    output = cases.map { |name, raw| outcome(name, raw).merge(saj: saj(raw)) }
    FileUtils.mkdir_p(path.dirname)
    FixtureRecording.verify(path, "#{JSON.pretty_generate(output)}\n")
    expect(output.size).to eq(cases.size)
  end
end
