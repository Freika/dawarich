# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Maps::TileUsage::Track do
  describe '#call' do
    subject(:track) { described_class.new(tile_count).call }

    let(:tile_count) { 5 }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
    end

    it 'tracks tile usage' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'counter',
          name: 'dawarich_map_tiles',
          value: tile_count
        }
      )

      track
    end
  end
end
