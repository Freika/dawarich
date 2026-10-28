# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit actions taken on a later day of an overnight visit', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:place) do
    create(:place, user: user, name: 'Synthetic ocean stop', latitude: -40.12345, longitude: -140.12345)
  end
  let!(:overnight) do
    create(:visit, user: user, place: place, name: 'Synthetic night', status: :suggested,
                   started_at: Time.utc(2026, 10, 20, 22, 0), ended_at: Time.utc(2026, 10, 21, 8, 0), duration: 600)
  end
  let!(:morning) do
    create(:visit, user: user, place: place, name: 'Synthetic morning', status: :suggested,
                   started_at: Time.utc(2026, 10, 21, 8, 5), ended_at: Time.utc(2026, 10, 21, 9, 0), duration: 55)
  end
  let!(:evening_before) do
    create(:visit, user: user, place: place, name: 'Synthetic dinner', status: :suggested,
                   started_at: Time.utc(2026, 10, 20, 19, 0), ended_at: Time.utc(2026, 10, 20, 20, 0), duration: 60)
  end

  before { sign_in user }

  def feed_frame_html
    Nokogiri::HTML(response.body).at_css('turbo-stream[target="timeline-feed-frame"] template')&.inner_html.to_s
  end

  it 'refreshes the viewed day after deleting the carried-over visit there' do
    delete bulk_destroy_visits_url(format: :turbo_stream), params: { visit_ids: [overnight.id], date: '2026-10-21' }

    expect(response).to have_http_status(:ok)
    expect(feed_frame_html).to include('Synthetic morning')
    expect(feed_frame_html).not_to include('Synthetic dinner')
  end

  it 'merges the carried-over visit with a visit that starts on the viewed day' do
    post merge_visits_url(format: :turbo_stream), params: { visit_ids: [overnight.id, morning.id], date: '2026-10-21' }

    expect(response).to have_http_status(:ok)
    expect(user.scoped_visits.where(id: [overnight.id, morning.id]).count).to eq(1)
    expect(feed_frame_html).not_to include('Synthetic dinner')
  end

  it 'still refuses to merge visits that share no day' do
    post merge_visits_url(format: :turbo_stream), params: { visit_ids: [evening_before.id, morning.id] }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "confirms the carried-over visit with the rest of the viewed day's suggestions" do
    patch bulk_update_visits_url(format: :turbo_stream),
          params: { status: 'confirmed', source_status: 'suggested', date: '2026-10-21' }

    expect([overnight, morning, evening_before].map { |v| v.reload.status })
      .to eq(%w[confirmed confirmed suggested])
  end

  it 'refreshes the calendar of the viewed month after deleting a visit that began the month before' do
    month_crossing = create(:visit, user: user, place: place, name: 'Synthetic month end', status: :suggested,
                                    started_at: Time.utc(2026, 9, 30, 22, 0), ended_at: Time.utc(2026, 10, 1, 7, 0),
                                    duration: 540)
    Timeline::MonthSummary.new(user: user, month: '2026-10').call

    delete visit_url(month_crossing), params: { date: '2026-10-01' }, as: :turbo_stream

    calendar = Nokogiri::HTML(response.body).at_css('turbo-stream[target="timeline-calendar-frame"]').to_html
    expect(calendar).to include('month=2026-11')
  end

  it 'clears the cached next month after a bulk delete of a visit that crosses into it' do
    month_crossing = create(:visit, user: user, place: place, name: 'Synthetic month end', status: :suggested,
                                    started_at: Time.utc(2026, 9, 30, 22, 0), ended_at: Time.utc(2026, 10, 1, 7, 0),
                                    duration: 540)
    Timeline::MonthSummary.new(user: user, month: '2026-10').call

    delete bulk_destroy_visits_url(format: :turbo_stream), params: { visit_ids: [month_crossing.id] }

    expect(Timeline::MonthSummary.new(user: user, month: '2026-10').call[:days]['2026-10-01']).to be_nil
  end

  it "keeps the row showing the viewed day's part after renaming it there" do
    patch visit_url(overnight), params: { visit: { name: 'Renamed night' }, date: '2026-10-21' }, as: :turbo_stream

    row = Nokogiri::HTML(response.body).at_css("turbo-stream[target=\"visit_entry_#{overnight.id}\"] template li")
    expect(row.at_css('.visit-row__time').text.squish).to eq('00:00')
    expect(row.at_css('.visit-row__duration').text.squish).to eq('8h')
  end
end
