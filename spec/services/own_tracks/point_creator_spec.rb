# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::PointCreator do
  subject(:call_service) { described_class.new(point_params, user.id).call }

  let(:user) { create(:user) }
  let(:file_path) { 'spec/fixtures/files/owntracks/2024-03.rec' }
  let(:point_params) { OwnTracks::RecParser.new(File.read(file_path)).call.first }

  it 'creates a point immediately' do
    expect { call_service }.to change { Point.where(user:).count }.by(1)
  end

  it 'returns created point coordinates' do
    result = call_service

    expect(result.first).to include('id', 'timestamp', 'longitude', 'latitude')
  end

  it 'avoids duplicate points' do
    call_service

    expect { call_service }.not_to(change { Point.where(user:).count })
  end

  it 'does not inflate points_count on duplicate submissions' do
    call_service
    user.reload
    count_after_first = user.points_count

    expect do
      call_service
      user.reload
    end.not_to(change { user.points_count })
    expect(user.points_count).to eq(count_after_first)
  end

  it 'updates points_count to match actual point count' do
    call_service
    user.reload

    expect(user.points_count).to eq(Point.where(user_id: user.id).count)
  end

  it 'enqueues VisitSuggestingJob when reverse geocoding is enabled (regression for #1749)' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)

    expect { call_service }.to have_enqueued_job(VisitSuggestingJob)
      .with(hash_including(user_id: user.id))
  end

  it 'does not enqueue VisitSuggestingJob when reverse geocoding is disabled' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

    expect { call_service }.not_to have_enqueued_job(VisitSuggestingJob)
  end

  context 'when params are invalid' do
    let(:point_params) { { lat: nil } }

    it 'returns an empty array' do
      expect(call_service).to eq([])
    end
  end
end
