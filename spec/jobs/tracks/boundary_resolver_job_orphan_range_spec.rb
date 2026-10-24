# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BoundaryResolverJob, 'with untracked points inside old tracks' do
  let(:user) { create(:user) }
  let(:start) { 1.year.ago.beginning_of_day + 10.hours }
  let!(:old_track) do
    create(:track, user: user, tracker_id: 'phone', start_at: start, end_at: start + 20.minutes, created_at: 2.days.ago)
  end
  let!(:late_point) do
    create(:point, user: user, tracker_id: 'phone', timestamp: (start + 10.minutes).to_i, created_at: 5.minutes.ago)
  end

  before do
    [start, start + 20.minutes].each do |at|
      create(:point, user: user, tracker_id: 'phone', track: old_track, timestamp: at.to_i)
    end
  end

  def resolve(metadata)
    session = Tracks::SessionManager.create_for_user(user.id, metadata)
    session.mark_started(1)
    session.increment_completed_chunks
    described_class.perform_now(user.id, session.session_id)
  end

  let(:range) { { start_at: start.beginning_of_day.iso8601, end_at: start.end_of_day.iso8601 } }

  it 'attaches the point after a session over untracked points only' do
    resolve(range.merge(untracked_only: true))

    expect(late_point.reload.track_id).to eq(old_track.id)
  end

  it 'leaves the point alone after a full rebuild session' do
    resolve(range.merge(untracked_only: false))

    expect(late_point.reload.track_id).to be_nil
  end

  it 'leaves the point alone when the session has no range' do
    resolve(untracked_only: true)

    expect(late_point.reload.track_id).to be_nil
  end
end
