# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip list state kept between the list and a trip', type: :request do
  let(:user) { create(:user) }
  let!(:trips) do
    Array.new(7) do |i|
      create(:trip, user:, name: "Trip #{i}", started_at: (i + 2).days.ago, ended_at: (i + 1).days.ago)
    end
  end
  let(:trip) { trips.first }

  before { sign_in user }

  def query_of(href)
    Rack::Utils.parse_query(URI.parse(href).query.to_s)
  end

  def html
    Nokogiri::HTML(response.body)
  end

  def back_link_href
    html.css('a').find { _1.text.include?(I18n.t('trips.show.back_to_trips')) }&.[]('href')
  end

  it 'links each trip card with the list page, family page and filters' do
    get trips_path(page: 2, family_page: 3, sort: 'name', q: 'Trip')

    card_hrefs = html.css('[data-trip-id]').map { _1.ancestors('a').first['href'] }

    expect(card_hrefs).not_to be_empty
    expect(card_hrefs.map { query_of(_1) }.uniq)
      .to eq([{ 'page' => '2', 'family_page' => '3', 'sort' => 'name', 'q' => 'Trip' }])
  end

  it 'leaves blank filters out of the trip card links' do
    get trips_path(q: '', year: '', month: '', sort: 'newest', page: 2)

    href = html.at_css('[data-trip-id]').ancestors('a').first['href']
    expect(query_of(href)).to eq('sort' => 'newest', 'page' => '2')
  end

  it 'sends "Back to trips" to the list state the trip was opened from' do
    get trip_path(trip, page: 2, family_page: 3, sort: 'name', year: '2024', origin: 'manual')

    expect(back_link_href)
      .to eq(trips_path(page: 2, family_page: 3, sort: 'name', year: '2024', origin: 'manual'))
  end

  it 'keeps only the whitelisted scalar list params on the back link' do
    get trip_path(trip, page: 2, host: 'evil.example', anchor: 'x', evil: '1',
                        'country' => { 'a' => 'b' }, 'family_page' => ['3'])

    expect(back_link_href).to eq(trips_path(page: 2))
  end

  it 'links "Back to trips" to the plain list when the trip was opened without list state' do
    get trip_path(trip)

    expect(back_link_href).to eq(trips_path)
  end

  it 'keeps the list state through editing the trip' do
    get trip_path(trip, page: 2, sort: 'name')
    edit_href = html.at_css("a[href^='#{edit_trip_path(trip)}']")['href']
    expect(query_of(edit_href)).to eq('page' => '2', 'sort' => 'name')

    get edit_href
    form = html.at_css("form[action='#{trip_path(trip)}']")
    hidden = form.css('input[type=hidden]').to_h { [_1['name'], _1['value']] }
    expect(hidden).to include('page' => '2', 'sort' => 'name')
    expect(query_of(form.css('a').find { _1['href'].start_with?(trip_path(trip)) }['href']))
      .to eq('page' => '2', 'sort' => 'name')

    patch trip_path(trip), params: { trip: { name: 'Renamed' }, page: '2', sort: 'name' }

    expect(response).to redirect_to(trip_path(trip, page: 2, sort: 'name'))
  end

  it 'keeps the list state in the form when an update fails' do
    patch trip_path(trip), params: { trip: { name: '' }, page: '2', sort: 'name' }

    expect(response).to have_http_status(:unprocessable_content)
    hidden = html.css("form[action='#{trip_path(trip)}'] input[type=hidden]").to_h { [_1['name'], _1['value']] }
    expect(hidden).to include('page' => '2', 'sort' => 'name')
  end

  it 'renders no list state in the new trip form' do
    get new_trip_path

    form = html.at_css("form[action='#{trips_path}']")
    expect(form.css('input[type=hidden]').map { _1['name'] }).not_to include('page', 'sort', 'q')
    expect(form.css('a').map { _1['href'] }).to include(trips_path)
  end
end
