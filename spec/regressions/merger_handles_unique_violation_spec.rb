# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracks::Merger under unique-index conflict', :non_transactional do
  let(:user) { create(:user) }

  let(:older_start) { Time.zone.parse('2026-04-01 10:00:00') }
  let(:older_end)   { Time.zone.parse('2026-04-01 10:05:00') }
  let(:newer_start) { Time.zone.parse('2026-04-01 10:06:00') }
  let(:newer_end)   { Time.zone.parse('2026-04-01 10:10:00') }

  def make_track(start_at:, end_at:)
    Track.create!(
      user_id: user.id,
      start_at: start_at,
      end_at: end_at,
      original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
      distance: 100,
      duration: (end_at - start_at).to_i,
      avg_speed: 10
    )
  end

  it 'returns false and preserves both tracks when merge target collides with the unique index' do
    older = make_track(start_at: older_start, end_at: older_end)
    newer = make_track(start_at: newer_start, end_at: newer_end)
    make_track(start_at: older_start, end_at: newer_end)

    result = Tracks::Merger.new(older, newer).call

    expect(result).to be false
    expect(Track.where(id: older.id).first.end_at).to eq(older_end)
    expect(Track.where(id: newer.id)).to exist
  end
end
