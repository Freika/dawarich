# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::Evaluator::ForPoint do
  let(:user) { create(:user) }
  let!(:area) { create(:area, user: user, latitude: 52.5, longitude: 13.4, radius: 100) }

  before { GeofenceEvents::Evaluator::StateStore.reset!(user) }

  def build_point(lat:, lon:, accuracy: 10)
    Point.new(
      user: user,
      lonlat: "POINT(#{lon} #{lat})",
      accuracy: accuracy,
      timestamp: Time.current.to_i
    )
  end

  describe '.call' do
    it 'records an enter event when point is within the radius' do
      point = build_point(lat: 52.5, lon: 13.4)
      expect { described_class.call(user, point) }.to change(GeofenceEvent, :count).by(1)
      expect(GeofenceEvent.last.event_type).to eq('enter')
    end

    it 'does not record anything for points outside the radius' do
      point = build_point(lat: 53.0, lon: 14.0)
      expect { described_class.call(user, point) }.not_to change(GeofenceEvent, :count)
    end

    it 'records a leave event after user moves out of area' do
      described_class.call(user, build_point(lat: 52.5, lon: 13.4))
      expect { described_class.call(user, build_point(lat: 53.0, lon: 14.0)) }
        .to change(GeofenceEvent, :count).by(1)
      expect(GeofenceEvent.last.event_type).to eq('leave')
    end

    it 'skips evaluation when accuracy > 500m' do
      point = build_point(lat: 52.5, lon: 13.4, accuracy: 1000)
      expect { described_class.call(user, point) }.not_to change(GeofenceEvent, :count)
    end

    it 'fails open when Redis is unavailable' do
      allow(GeofenceEvents::Evaluator::StateStore).to receive(:currently_inside)
        .and_raise(Redis::CannotConnectError)
      expect(Sentry).to receive(:capture_exception)
      expect {
        described_class.call(user, build_point(lat: 52.5, lon: 13.4))
      }.not_to raise_error
    end

    it 'does not fire duplicate enter for subsequent inside points' do
      described_class.call(user, build_point(lat: 52.5, lon: 13.4))
      expect {
        described_class.call(user, build_point(lat: 52.5001, lon: 13.4001))
      }.not_to change(GeofenceEvent, :count)
    end
  end
end
