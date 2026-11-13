# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'map/timeline_feeds/_day', 'map notes' do
  let(:user) { create(:user) }
  let(:summary) do
    { total_distance: 0, distance_unit: 'km', places_visited: 1, time_moving_minutes: 0,
      time_stationary_minutes: 60, mode_distances: {}, facts: 'Home → Office · 8.5 km' }
  end
  let(:visit) do
    { type: 'visit', visit_id: 1, name: 'Home', status: 'confirmed', point_count: 12, tags: [],
      started_at: '2026-02-23T12:00:00+00:00', ended_at: '2026-02-23T13:00:00+00:00',
      duration: 60, place: nil, area: nil }
  end
  let(:notes) do
    [{ note_id: 7, body: "Before lunch\nsecond line", noted_at: '2026-02-23T09:00:00+00:00', latitude: 1.0,
       longitude: 2.0 },
     { note_id: 8, body: 'After lunch', noted_at: '2026-02-23T15:00:00+00:00', latitude: nil, longitude: nil }]
  end
  let(:entries) { [visit] }
  let(:day) { { date: '2026-02-23', summary: summary, bounds: nil, entries: entries, notes: notes } }

  before do
    allow(view).to receive(:current_user).and_return(user)
    render partial: 'map/timeline_feeds/day', locals: { day: day }
  end

  it 'shows the facts line of the day' do
    expect(rendered).to have_css('.timeline-day-facts', text: 'Home → Office · 8.5 km')
  end

  it 'places each note between the entries by its time' do
    rows = Capybara.string(rendered).all('.timeline-entries > *').map { |row| row['data-entry-type'] }

    expect(rows).to eq(%w[note visit note])
    expect(rendered).to have_css('.note-leg__body', text: 'Before lunch')
  end

  it 'opens a note in the map note dialog' do
    expect(rendered).to have_css("a[href='#{edit_note_path(7)}'][data-turbo-frame='map-note-form']")
  end

  context 'when the day has a note and nothing else' do
    let(:entries) { [] }
    let(:summary) { super().merge(facts: nil) }

    it 'shows the note instead of the empty state' do
      expect(rendered).to have_css('.note-leg__body', text: 'After lunch')
      expect(rendered).not_to have_css('.timeline-day-facts')
      expect(rendered).not_to have_text('No visits tracked')
    end
  end
end
