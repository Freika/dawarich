# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::Evaluator do
  let(:user) { create(:user) }
  let!(:area) { create(:area, user:, latitude: 52.52, longitude: 13.405, radius: 100) }
  let(:start) { 1_760_000_000 }

  before { GeofenceEvents::StateStore.new(user).reset! }

  def at(lon, minute, accuracy: 10)
    { lonlat: "POINT(#{lon} 52.52)", timestamp: start + (minute * 60), accuracy: }
  end

  def ingest(*payloads, mode: :realtime)
    Points::Intake.call(user_id: user.id, payloads:, mode:)
  end

  def events
    GeofenceEvent.where(user:).order(:occurred_at).pluck(:event_type)
  end

  it 'enters at the radius and leaves only beyond the hysteresis band' do
    ingest(at(13.4100, 0), at(13.4050, 1), at(13.4067, 2), at(13.4100, 3))

    expect(events).to eq(%w[enter leave])
    expect(GeofenceEvent.pluck(:occurred_at).map(&:to_i)).to eq([start + 60, start + 180])
  end

  it 'holds the visit while a point stays inside the band' do
    ingest(at(13.4050, 0), at(13.4067, 1), at(13.4068, 2, accuracy: nil))

    expect(events).to eq(%w[enter])
  end

  it 'ignores points with poor accuracy' do
    ingest(at(13.4050, 0, accuracy: 600))

    expect(events).to be_empty
  end

  it 'ignores a point older than one already evaluated' do
    ingest(at(13.4100, 5))
    ingest(at(13.4050, 1))

    expect(events).to be_empty
  end

  it 'evaluates across separate requests' do
    ingest(at(13.4050, 0))
    ingest(at(13.4100, 1))

    expect(events).to eq(%w[enter leave])
  end

  it 'never evaluates bulk imports' do
    ingest(at(13.4100, 0), at(13.4050, 1), mode: :bulk)

    expect(events).to be_empty
  end

  it 'never leaves an area that was deleted' do
    ingest(at(13.4050, 0))
    area.destroy!

    expect { ingest(at(13.4100, 1)) }.not_to raise_error
    expect(GeofenceEvent.count).to eq(0)
  end

  it 'keeps ingesting when evaluation fails' do
    allow(GeofenceEvents::StateStore).to receive(:new).and_raise(StandardError, 'boom')

    expect { ingest(at(13.4050, 0)) }.to change(Point, :count).by(1)
  end

  it 'only checks for areas for a user without any' do
    other = create(:user)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      described_class.call(user_id: other.id, rows: [{ 'id' => 1, 'xmax' => '0', 'timestamp' => start,
                                                      'longitude' => 13.405, 'latitude' => 52.52 }], payloads: [])
    end

    expect(statements.size).to eq(1)
    expect(statements.first).to include('"areas"')
  end
end
