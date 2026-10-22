# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::SajParser do
  let(:handler_class) do
    Class.new(Oj::Saj) do
      attr_reader :values

      def initialize
        super
        @values = []
      end

      def hash_start(key = nil, *_); end
      def hash_end(key = nil, *_); end
      def array_start(key = nil, *_); end
      def array_end(key = nil, *_); end

      def add_value(value, key)
        @values << [key, value]
      end
    end
  end

  let(:handler) { handler_class.new }

  def parse(json)
    described_class.parse(StringIO.new(json.b), handler)
    handler.values
  end

  it 'streams a valid document without the buffering legacy parser' do
    expect(Oj).not_to receive(:saj_parse)

    expect(parse('{"points":[{"a":1,"b":"x"}],"c":true}')).to eq([['a', 1], %w[b x], ['c', true]])
  end

  it 'keeps the decimal point in long fractional numbers' do
    values = parse('{"a":-0.40511831641197205,"b":0.36759892106056213,"c":52.520008000000004}').to_h

    expect(values.transform_values(&:to_f)).to eq('a' => -0.40511831641197205, 'b' => 0.36759892106056213,
                                                  'c' => 52.520008000000004)
  end

  it 'falls back to the legacy parser for bytes the strict parser rejects' do
    expect(parse("{\"a\":\"\xff\",\"b\":2}")).to include(['b', 2])
  end

  it 'raises Oj::ParseError for a truncated document' do
    expect { parse('{"a":[1,2') }.to raise_error(Oj::ParseError)
  end
end
