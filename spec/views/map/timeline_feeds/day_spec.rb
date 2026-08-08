# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'map/timeline_feeds/_day' do
  let(:user) { create(:user) }

  def visit_entry(id:, name:, start_hm:, end_hm:, duration:, points: 12)
    {
      type: 'visit', visit_id: id, name: name, status: 'confirmed', point_count: points, tags: [],
      started_at: "2026-02-23T#{start_hm}:00+00:00", ended_at: "2026-02-23T#{end_hm}:00+00:00",
      duration: duration, place: nil, area: nil
    }
  end

  def journey_entry(id:, mode:, start_hm:, end_hm:, duration:, distance:)
    {
      type: 'journey', track_id: id, started_at: "2026-02-23T#{start_hm}:00+00:00",
      ended_at: "2026-02-23T#{end_hm}:00+00:00", duration: duration, distance: distance,
      distance_unit: 'km', dominant_mode: mode, avg_speed: 40.0, speed_unit: 'km/h',
      elevation_gain: 0, elevation_loss: 0, continuation_of_date: nil,
      day_distance: nil, day_duration: nil, moving_duration: duration
    }
  end

  let(:entries) do
    [
      visit_entry(id: 1, name: 'Saturn, Przemysłowa, Krakow, Lesser Poland Voivodeship',
                  start_hm: '09:59', end_hm: '10:24', duration: 24, points: 33),
      journey_entry(id: 11, mode: 'driving', start_hm: '11:23', end_hm: '14:43',
                    duration: 12_000, distance: 170.1),
      visit_entry(id: 2, name: 'Arge, Chyżne, Lesser Poland Voivodeship',
                  start_hm: '13:06', end_hm: '13:16', duration: 10, points: 17),
      visit_entry(id: 3, name: 'Jurki, Poľnohospodárska, Demänová, Region of Žilina',
                  start_hm: '18:59', end_hm: '19:14', duration: 14, points: 35)
    ]
  end

  let(:day) do
    {
      date: '2026-02-23',
      summary: {
        total_distance: 178.5, distance_unit: 'km', places_visited: 3,
        time_moving_minutes: 249, time_stationary_minutes: 48,
        suggested_count: 0, confirmed_count: 3, declined_count: 0,
        mode_distances: { 'driving' => 178.5, 'walking' => 0.7 }
      },
      bounds: nil,
      entries: entries
    }
  end

  before do
    allow(view).to receive(:current_user).and_return(user)
    render partial: 'map/timeline_feeds/day', locals: { day: day }
  end

  it 'leads each visit with the recognizable part of the geocoded name' do
    expect(rendered).to have_css('.visit-row__title', text: 'Saturn')
    expect(rendered).to have_css('.visit-row__address', text: 'Przemysłowa, Krakow')
  end

  it 'keeps the administrative tail out of the visible row' do
    expect(rendered).not_to have_css('.visit-row__content', text: 'Voivodeship')
  end

  it 'still exposes the full geocoded string so search and screen readers keep it' do
    # Condensing what is shown must not shrink what is findable.
    expect(rendered).to have_css("[data-search-tokens*='lesser poland voivodeship']")
    expect(rendered).to have_css("[aria-label*='Lesser Poland Voivodeship']", visible: :all)
  end

  it 'names the untracked stretch between the last drive and the evening visit' do
    expect(rendered).to have_css('.timeline-entry--gap', count: 1)
    expect(rendered).to have_css('.gap-leg__summary', text: '4h 16m untracked')
  end

  it 'does not invent a gap inside a journey that overlaps the visit within it' do
    # The 11:23–14:43 drive covers the 13:06 visit, and the 59m seam before it
    # is below the threshold. Only the 14:43 → 18:59 hole is worth naming.
    expect(rendered).to have_css('.timeline-entry--gap', count: 1)
  end

  it 'sizes a leg by its duration so time reads as vertical distance' do
    expect(rendered).to have_css('.timeline-entry--journey[style*="--tl-leg-extra"]')
  end

  it 'draws day mode chips with icons rather than emoji' do
    expect(rendered).to have_css('.mode-chip .mode-chip__icon', count: 2)
    expect(rendered).not_to include('🚗')
  end

  it 'prints each visit duration once, opposite its arrival time' do
    expect(rendered).to have_css('.visit-row__duration', text: '24m')
  end
end
