# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'tracks unique index allows two devices with the same start/end window' do
  let(:user) { create(:user) }
  let(:start_at) { 1.hour.ago.beginning_of_minute }
  let(:end_at) { start_at + 30.minutes }

  it 'two tracks for one user with the same start/end coexist when tracker_id differs' do
    create(:track, user: user, tracker_id: 'iphone', start_at: start_at, end_at: end_at)

    expect do
      create(:track, user: user, tracker_id: 'watch', start_at: start_at, end_at: end_at)
    end.not_to raise_error

    expect(user.tracks.where(start_at: start_at, end_at: end_at).count).to eq(2)
  end

  it 'two tracks for one user with the same tracker_id and same start/end still collide' do
    create(:track, user: user, tracker_id: 'iphone', start_at: start_at, end_at: end_at)

    expect do
      create(:track, user: user, tracker_id: 'iphone', start_at: start_at, end_at: end_at)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'two tracks with NULL tracker_id and same start/end still collide (NULLS NOT DISTINCT)' do
    create(:track, user: user, tracker_id: nil, start_at: start_at, end_at: end_at)

    expect do
      create(:track, user: user, tracker_id: nil, start_at: start_at, end_at: end_at)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
