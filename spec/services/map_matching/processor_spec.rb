# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::Processor do
  let(:client) { instance_double(MapMatching::Atlas::Client) }
  let(:points) do
    [
      MapMatching::Input::Point.new(id: 1, timestamp: 100, lon: 13.4, lat: 52.5, accuracy: 5.0),
      MapMatching::Input::Point.new(id: 2, timestamp: 110, lon: 13.41, lat: 52.51, accuracy: 5.0)
    ]
  end
  let(:walking) do
    MapMatching::Input::Portion.new(
      key: 'segment:1', transportation_mode: 'walking', atlas_mode: 'pedestrian',
      points:, start_index: 0, end_index: 1
    )
  end
  let(:train) do
    MapMatching::Input::Portion.new(
      key: 'segment:2', transportation_mode: 'train', atlas_mode: nil,
      points:, start_index: 0, end_index: 1
    )
  end

  before do
    allow(client).to receive(:version).and_return(version: '0.6.0', revision: 'abc')
    allow(client).to receive(:map_match)
  end

  it 'publishes a fully matched composite when every portion is accepted' do
    input = instance_double(MapMatching::Input, eligible?: true, portions: [walking])
    response = atlas_result(
      geometry: {
        'type' => 'LineString',
        'coordinates' => [[13.4, 52.5], [13.405, 52.505]]
      },
      stats: { 'matched' => 2, 'unmatched' => 0 }
    )
    allow(client).to receive(:map_match).and_return(response)

    result = described_class.new(input, client:).call

    expect(result.status).to eq(:matched)
    expect(result.path.num_geometries).to eq(1)
    expect(result.data.dig(:provider, :version)).to eq('0.6.0')
    expect(result.data.dig(:segments, 0, :result)).to eq('accepted')
  end

  it 'preserves unsupported portions and reports a partial result' do
    input = instance_double(MapMatching::Input, eligible?: true, portions: [walking, train])
    response = atlas_result(
      geometry: {
        'type' => 'MultiLineString',
        'coordinates' => [
          [[13.4, 52.5], [13.405, 52.505]],
          [[13.406, 52.506], [13.41, 52.51]]
        ]
      },
      stats: { 'matched' => 2 }
    )
    allow(client).to receive(:map_match).and_return(response)

    result = described_class.new(input, client:).call

    expect(result.status).to eq(:partial)
    expect(result.path.num_geometries).to eq(3)
    expect(result.data[:segments].last[:result]).to eq('unsupported')
  end

  it 'falls back and rejects when Atlas returns a terminal input error' do
    input = instance_double(MapMatching::Input, eligible?: true, portions: [walking])
    allow(client).to receive(:map_match).and_raise(
      MapMatching::Atlas::Client::InvalidRequest.new('bad input', code: 'invalid_input', status: 422)
    )

    result = described_class.new(input, client:).call

    expect(result.status).to eq(:rejected)
    expect(result.path).to be_nil
    expect(result.data.dig(:segments, 0, :reasons)).to eq(['invalid_input'])
  end

  it 'does not call Atlas for an oversized portion' do
    oversized = walking.with(points: Array.new(described_class::MAX_POINTS + 1, points.first))
    input = instance_double(MapMatching::Input, eligible?: true, portions: [oversized])

    result = described_class.new(input, client:).call

    expect(client).not_to have_received(:map_match)
    expect(result.status).to eq(:rejected)
    expect(result.data.dig(:segments, 0, :reasons)).to eq(['too_many_points'])
  end

  def atlas_result(geometry:, stats:)
    MapMatching::Atlas::Client::Result.new(geometry:, stats:, meta: {})
  end
end
