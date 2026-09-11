# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point ingest timestamp formats' do
  let(:unix_timestamp) { 1_788_930_000 }
  let(:iso8601_timestamp) { '2026-09-09T05:00:00Z' }

  def location(timestamp)
    {
      geometry: { coordinates: [13.4, 52.5] },
      properties: { timestamp: }
    }
  end

  shared_examples 'timestamp-compatible point params' do
    it 'accepts Unix timestamp strings and integers' do
      expect(parse.call('1788930000').fetch(:timestamp).to_i).to eq(unix_timestamp)
      expect(parse.call(unix_timestamp).fetch(:timestamp).to_i).to eq(unix_timestamp)
    end

    it 'accepts ISO 8601 timestamps' do
      expect(parse.call(iso8601_timestamp).fetch(:timestamp).to_i).to eq(unix_timestamp)
    end

    it 'rejects malformed and out-of-range timestamps' do
      invalid_values = ['not-a-timestamp', '2026-02-30T12:00:00Z', '2147483648', '2038-01-19T03:14:08Z']

      invalid_values.each do |value|
        expect { parse_all.call(value) }
          .to raise_error(Points::TimestampParser::InvalidTimestampError)
      end
    end

    it 'accepts the timestamp storage boundaries' do
      expect(parse.call('-2147483648').fetch(:timestamp).to_i).to eq(-2_147_483_648)
      expect(parse.call('2147483647').fetch(:timestamp).to_i).to eq(2_147_483_647)
    end
  end

  context 'with Overland parameters' do
    let(:parse_all) { ->(timestamp) { Overland::Params.new(locations: [location(timestamp)]).call } }
    let(:parse) { ->(timestamp) { parse_all.call(timestamp).first } }

    include_examples 'timestamp-compatible point params'
  end

  context 'with generic point parameters' do
    let(:parse_all) { ->(timestamp) { Points::Params.new({ locations: [location(timestamp)] }, 1).call } }
    let(:parse) { ->(timestamp) { parse_all.call(timestamp).first } }

    include_examples 'timestamp-compatible point params'
  end
end
