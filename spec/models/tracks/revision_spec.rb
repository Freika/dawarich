# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Revision do
  let(:user) { create(:user) }

  def revisions
    described_class.where(user_id: user.id).order(:month).pluck(:month, :revision).to_h
  end

  def digest(start_at, end_at)
    described_class.for_user(user.id, start_at: start_at.to_i, end_at: end_at.to_i)
  end

  it 'records every month a track spans' do
    create(:track, user:, start_at: Time.utc(2024, 1, 31, 23), end_at: Time.utc(2024, 3, 1, 1))

    expect(revisions.keys).to eq([Date.new(2024, 1, 1), Date.new(2024, 2, 1), Date.new(2024, 3, 1)])
  end

  it 'changes the months of a track that is updated without callbacks, and only those' do
    track = create(:track, user:, start_at: Time.utc(2024, 6, 1, 10), end_at: Time.utc(2024, 6, 1, 12))
    create(:track, user:, start_at: Time.utc(2024, 9, 1, 10), end_at: Time.utc(2024, 9, 1, 12))
    june = digest(Time.utc(2024, 6, 1), Time.utc(2024, 6, 30))
    september = digest(Time.utc(2024, 9, 1), Time.utc(2024, 9, 30))

    Track.where(id: track.id).update_all(distance: 42)

    expect(digest(Time.utc(2024, 6, 1), Time.utc(2024, 6, 30))).not_to eq(june)
    expect(digest(Time.utc(2024, 9, 1), Time.utc(2024, 9, 30))).to eq(september)
  end

  it 'covers both the old and the new months when a track is moved' do
    track = create(:track, user:, start_at: Time.utc(2024, 6, 1, 10), end_at: Time.utc(2024, 6, 1, 12))
    june = digest(Time.utc(2024, 6, 1), Time.utc(2024, 6, 30))

    Track.where(id: track.id).update_all(start_at: Time.utc(2024, 8, 1, 10), end_at: Time.utc(2024, 8, 1, 12))

    expect(digest(Time.utc(2024, 6, 1), Time.utc(2024, 6, 30))).not_to eq(june)
    expect(revisions.keys).to include(Date.new(2024, 8, 1))
  end

  it 'changes the revision when a track is deleted' do
    track = create(:track, user:, start_at: Time.utc(2024, 6, 1, 10), end_at: Time.utc(2024, 6, 1, 12))
    june = digest(Time.utc(2024, 6, 1), Time.utc(2024, 6, 30))

    Track.where(id: track.id).delete_all

    expect(digest(Time.utc(2024, 6, 1), Time.utc(2024, 6, 30))).not_to eq(june)
  end
end
