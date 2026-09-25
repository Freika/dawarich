# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::CleanupNullIslandJob do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  let!(:zero_point) do
    create(:point, user: user, latitude: 0.0, longitude: 0.0,
                   lonlat: 'POINT(0.0 0.0)', track: track,
                   timestamp: Time.zone.local(2024, 5, 10, 12).to_i)
  end
  let!(:normal_point) do
    create(:point, user: user, latitude: 52.5, longitude: 13.4,
                   lonlat: 'POINT(13.4 52.5)',
                   timestamp: Time.zone.local(2024, 5, 10, 13).to_i)
  end

  let(:zero_place) { create(:place, latitude: 0.0, longitude: 0.0, lonlat: 'POINT(0.0 0.0)') }
  let(:normal_place) { create(:place) }
  let!(:zero_visit) { create(:visit, user: user, place: zero_place) }
  let!(:normal_visit) { create(:visit, user: user, place: normal_place) }

  it 'flags (0,0) points as anomalies' do
    described_class.perform_now(user.id)

    expect(zero_point.reload.anomaly).to be(true)
    expect(normal_point.reload.anomaly).not_to be(true)
  end

  it 'destroys visits placed at (0,0) and keeps the rest' do
    expect { described_class.perform_now(user.id) }
      .to change { Visit.exists?(zero_visit.id) }.from(true).to(false)

    expect(Visit.exists?(normal_visit.id)).to be(true)
  end

  it 'enqueues stats recalculation for affected months and track recalculation' do
    expect { described_class.perform_now(user.id) }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 5)
      .and have_enqueued_job(Tracks::RecalculateJob).with(track.id)
  end

  describe 'fan out' do
    it 'enqueues a per-user job for every user with (0,0) points' do
      other_user = create(:user)
      create(:point, user: other_user, latitude: 0.0, longitude: 0.0,
                     lonlat: 'POINT(0.0 0.0)', timestamp: Time.zone.local(2024, 6, 1).to_i)

      expect { described_class.perform_now }
        .to have_enqueued_job(described_class).with(user.id)
        .and have_enqueued_job(described_class).with(other_user.id)
    end
  end
end
