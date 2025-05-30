# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Metrics::Maps::TileUsage::Track do
  describe '#call' do
    subject(:track) { described_class.new(user_id, tile_count).call }

    let(:user_id) { 1 }
    let(:tile_count) { 5 }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
      allow(prometheus_client).to receive(:send_json)
      allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
    end

    it 'tracks tile usage in prometheus' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'counter',
          name: 'dawarich_map_tiles_usage',
          value: tile_count
        }
      )

      track
    end

    it 'tracks tile usage in cache' do
      expect(Rails.cache).to receive(:write).with(
        "dawarich_map_tiles_usage:#{user_id}:#{Time.zone.today}",
        tile_count,
        expires_in: 7.days
      )

      track
    end
  end
end
