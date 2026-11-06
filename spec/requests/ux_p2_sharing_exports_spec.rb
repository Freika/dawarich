# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'P2 export and sharing journeys', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'timezone' => 'America/New_York' }) }
  before { sign_in user }

  around { |example| travel_to(Time.utc(2026, 10, 27, 12)) { example.run } }

  it 'carries the selected import from Points through to a downloaded export' do
    selected = create(:import, user: user)
    other = create(:import, user: user)
    2.times { |n| create(:point, user: user, import: selected, timestamp: Time.utc(2026, 4, 5, 12, n).to_i) }
    create(:point, user: user, import: other, timestamp: Time.utc(2026, 4, 5, 13).to_i)
    get points_path, params: { import_id: selected.id, start_at: '2026-04-05T00:00', end_at: '2026-04-05T23:59' }
    document = Nokogiri::HTML(response.body)
    url = document.css('button').find { |b| b['formaction']&.include?('file_format=json') }['formaction']
    form = document.at_css('#points_filter_form')
    fields = form.css('input[name], select[name]').to_h do |field|
      value = field.name == 'select' ? field.at_css('option[selected]')&.[]('value') : field['value']
      [field['name'], value]
    end
    post url, params: fields
    export = user.exports.last
    expect(export).to be_present
    export.process!
    expect(export.reload).to be_completed
    bytes = export.file.download
    Zip::InputStream.open(StringIO.new(bytes)) do |zip|
      zip.get_next_entry
      expect(JSON.parse(zip.read)['features'].length).to eq(2)
    end
  end

  it 'rejects exports of another user\'s import' do
    foreign = create(:import)
    expect do
      post exports_path, params: { import_id: foreign.id, file_format: :json,
                                  start_at: '2026-04-05T00:00', end_at: '2026-04-05T23:59' }
    end.not_to change(Export, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'opens Time period when sharing the selected historical map' do
    get map_v2_path, params: { start_at: '2026-04-05T00:00', end_at: '2026-04-05T23:59' }
    url = Nokogiri::HTML(response.body).at_css('[data-testid="timeline-share-button"]')['href']
    get url
    expect(Nokogiri::HTML(response.body).at_css('[data-controller="hub-tabs"]')['data-hub-tabs-active-value'])
      .to eq('timeline')
  end

  it 'expires at the start of the selected day in the owner timezone' do
    trip = create(:trip, user: user)
    post trip_share_link_path(trip), params: { shared_link: { expires_at: '2026-11-03' } }
    expect(user.shared_links.last.expires_at).to be_within(1.second)
      .of(Time.find_zone!('America/New_York').local(2026, 11, 3))
  end

  it 'lets the owner edit access without replacing the URL or import scope' do
    selected = create(:import, user: user)
    link = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                settings: { 'start_date' => '2026-04-05', 'end_date' => '2026-04-05',
                                            'import_id' => selected.id.to_s }, autobuild_trip: false)
    patch "/share_links/shares/#{link.id}", params: {
      shared_link: { expires_at: '2026-11-03', settings: { show_photos: '0' } }
    }
    expect(response).to have_http_status(:ok)
    expect(link.reload.settings['import_id']).to eq(selected.id.to_s)
    expect(link.expires_at).to be_present
    expect(user.shared_links.active.sole.id).to eq(link.id)
  end
  it 'preserves an existing exact expiry when the owner only changes sections' do
    trip = create(:trip, user: user)
    expires_at = Time.find_zone!('America/New_York').local(2026, 11, 3, 14)
    link = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id, expires_at: expires_at)
    get "/share_links/shares/#{link.id}/edit"
    input = Nokogiri::HTML(response.body).at_css('input[name="shared_link[expires_at]"]')
    patch "/share_links/shares/#{link.id}", params: {
      shared_link: { expires_at: input['value'].sub(/:00\z/, ''), settings: { show_photos: '0' } }
    }
    expect(response).to have_http_status(:ok)
    expect(link.reload.expires_at).to eq(expires_at)
  end
  it 'keeps the expiry when a partial access update omits the expiry field' do
    trip = create(:trip, user: user)
    expiry = Time.current + 2.days
    link = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id, expires_at: expiry)
    patch "/share_links/shares/#{link.id}", params: { shared_link: { settings: { show_photos: '0' } } }
    expect(response).to have_http_status(:ok)
    expect(link.reload.expires_at).to be_within(1.second).of(expiry)
  end

  it 'exports GPX within the same import scope and stays empty after the import is removed' do
    selected = create(:import, user: user)
    create(:point, user: user, import: selected, timestamp: Time.utc(2026, 4, 5, 12).to_i)
    create(:point, user: user, timestamp: Time.utc(2026, 4, 5, 13).to_i)
    post exports_path, params: { import_id: selected.id, file_format: :gpx,
                                start_at: '2026-04-05T00:00', end_at: '2026-04-05T23:59' }
    export = user.exports.last
    export.process!
    Zip::InputStream.open(StringIO.new(export.reload.file.download)) do |zip|
      zip.get_next_entry
      expect(zip.read.scan('<trkpt').size).to eq(1)
    end
    selected.destroy!
    export.process!
    Zip::InputStream.open(StringIO.new(export.reload.file.download)) do |zip|
      zip.get_next_entry
      expect(zip.read.scan('<trkpt').size).to eq(0)
    end
  end
end
