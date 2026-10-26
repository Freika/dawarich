# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::DayAssembler do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:place) do
    create(:place, user: user, name: 'Synthetic ocean stop', latitude: -40.12345, longitude: -140.12345)
  end
  let!(:visit) do
    create(:visit, user: user, place: place, name: 'Synthetic overnight stay', status: :suggested,
                   started_at: Time.utc(2026, 10, 20, 18, 45), ended_at: Time.utc(2026, 10, 22, 19, 24),
                   duration: 2919)
  end

  shared_examples 'a timeline containing the ongoing visit' do |first_day, last_day, expected_dates|
    it 'shows the visit location and counts it once on each overlapping day' do
      days = described_class.new(
        user,
        start_at: "#{first_day}T00:00:00Z",
        end_at: "#{last_day}T23:59:59Z"
      ).call

      expect(days).to match_array(expected_dates.map do |date|
        a_hash_including(
          date: date,
          entries: contain_exactly(a_hash_including(
                                     type: 'visit', visit_id: visit.id, name: 'Synthetic overnight stay',
                                     place: a_hash_including(name: 'Synthetic ocean stop')
                                   )),
          summary: a_hash_including(places_visited: 1, suggested_count: 1)
        )
      end)
    end
  end

  context 'when selecting the arrival day' do
    include_examples 'a timeline containing the ongoing visit', '2026-10-20', '2026-10-20', ['2026-10-20']
  end

  context 'when selecting the full day spent at the location' do
    include_examples 'a timeline containing the ongoing visit', '2026-10-21', '2026-10-21', ['2026-10-21']
  end

  context 'when selecting the departure day' do
    include_examples 'a timeline containing the ongoing visit', '2026-10-22', '2026-10-22', ['2026-10-22']
  end

  context 'when loading all three days together' do
    include_examples 'a timeline containing the ongoing visit', '2026-10-20', '2026-10-22',
                     %w[2026-10-20 2026-10-21 2026-10-22]
  end

  it 'splits the stay time between the days it covers' do
    days = described_class.new(user, start_at: '2026-10-20T00:00:00Z', end_at: '2026-10-22T23:59:59Z').call

    expect(days.to_h { |day| [day[:date], day[:summary][:time_stationary_minutes]] })
      .to eq('2026-10-20' => 315, '2026-10-21' => 1440, '2026-10-22' => 1164)
  end

  it 'keeps a visit that ends exactly at midnight off the next day' do
    midnight_visit = create(:visit, user: user, place: place, name: 'Synthetic evening stop',
                                    started_at: Time.utc(2026, 10, 18, 22, 0), ended_at: Time.utc(2026, 10, 19, 0, 0),
                                    duration: 120)

    days = described_class.new(user, start_at: '2026-10-19T00:00:00Z', end_at: '2026-10-19T23:59:59Z').call

    expect(days.flat_map { |day| day[:entries] }.pluck(:visit_id)).not_to include(midnight_visit.id)
  end

  it "marks the later days' rows as a continuation with that day's share of the stay" do
    days = described_class.new(user, start_at: '2026-10-20T00:00:00Z', end_at: '2026-10-22T23:59:59Z').call

    rows = days.to_h { |day| [day[:date], day[:entries].first.slice(:continuation_of_date, :day_duration)] }
    expect(rows).to eq(
      '2026-10-20' => { continuation_of_date: nil, day_duration: nil },
      '2026-10-21' => { continuation_of_date: '2026-10-20', day_duration: 1440 },
      '2026-10-22' => { continuation_of_date: '2026-10-20', day_duration: 1164 }
    )
  end
end

RSpec.describe 'Timeline feed rows for a visit that started on an earlier day', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:place) do
    create(:place, user: user, name: 'Synthetic ocean stop', latitude: -40.12345, longitude: -140.12345)
  end

  before do
    create(:visit, user: user, place: place, name: 'Synthetic overnight stay', status: :suggested,
                   started_at: Time.utc(2026, 10, 20, 18, 45), ended_at: Time.utc(2026, 10, 22, 19, 24),
                   duration: 2919)
    sign_in user
  end

  def visit_row_for(date)
    get map_timeline_feeds_path(start_at: "#{date}T00:00:00Z", end_at: "#{date}T23:59:59Z")
    Nokogiri::HTML(response.body).at_css('[data-testid="visit-row"]')
  end

  it 'shows the time from midnight and only the part of the stay on the departure day' do
    row = visit_row_for('2026-10-22')

    expect(row.at_css('.visit-row__time').text.squish).to eq('00:00')
    expect(row.at_css('.visit-row__duration').text.squish).to eq('19h 24m')
    expect(row.css('form input[name="date"]').map { |input| input['value'] }).to eq(%w[2026-10-22 2026-10-22])
  end

  it 'shows a day spent entirely at the place as all day' do
    row = visit_row_for('2026-10-21')

    expect(row.at_css('.visit-row__all-day')).to be_present
  end

  it 'keeps the arrival time and the whole stay on the arrival day of a short overnight visit' do
    Visit.delete_all
    create(:visit, user: user, place: place, name: 'Synthetic night', started_at: Time.utc(2026, 10, 20, 22, 0),
                   ended_at: Time.utc(2026, 10, 21, 8, 0), duration: 600)
    row = visit_row_for('2026-10-20')

    expect(row.at_css('.visit-row__time').text.squish).to eq('22:00')
    expect(row.at_css('.visit-row__duration').text.squish).to eq('10h')
  end
end
