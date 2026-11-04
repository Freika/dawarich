# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'P2 first-run and sharing feedback', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
  before { sign_in user }

  it 'selects exactly seven calendar dates including today' do
    travel_to(Time.utc(2026, 10, 27, 12)) do
      get map_v2_path
      link = Nokogiri::HTML(response.body).css('a').find { |a| a.text.strip == 'Last 7 days' }
      query = Rack::Utils.parse_query(URI.parse(link['href']).query)
      expect(Date.iso8601(query['end_at'].split('T').first) - Date.iso8601(query['start_at'].split('T').first)).to eq(6)
    end
  end

  it 'defers the changelog prompt until onboarding is complete' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    get map_v2_path
    expect(response.body).not_to include('Stay up to date?')
    patch settings_onboarding_path
    get map_v2_path
    expect(response.body).to include('Stay up to date?')
  end

  it 'explains a failed import and offers another upload on the import page' do
    import = create(:import, user: user, status: :failed, error_message: 'Unable to detect file format')
    get import_path(import)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('[data-testid="import-failure"]')&.text).to include('file format')
    expect(page.css('a').any? { |a| a['href'] == new_import_path }).to be(true)
  end

  it 'refreshes the member row along with the family sharing toggle' do
    family = create(:family, creator: user)
    create(:family_membership, family: family, user: user, role: :owner)
    patch location_sharing_family_path, params: { enabled: 'false' }, as: :turbo_stream
    stream = Nokogiri::HTML(response.body).at_css("turbo-stream[target='family-member-#{user.id}']")
    expect(stream&.text).to include('Not sharing')
  end

  it 'records a pending digest immediately and does not enqueue it twice' do
    create(:stat, user: user, year: 2025, month: 1)
    ActiveJob::Base.queue_adapter = :test
    expect do
      2.times do
        post users_digests_path, params: { year: 2025 }
        expect(response).to have_http_status(:see_other)
      end
    end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).exactly(:once)
    get users_digests_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('[data-digest-pending="2025"]')).to be_present
    expect(response.body).not_to include('No Year-End Digests Yet')
  end
  it 'turns an existing queued digest into a ready digest through the real job' do
    create(:stat, user: user, year: 2025, month: 1)
    digest = user.digests.yearly.create!(year: 2025, generation_status: :queued)
    Users::Digests::Yearly::CalculatingJob.perform_now(user.id, 2025)
    expect(digest.reload).to be_generation_ready
  end
  it 'keeps pending digests out of ready API data and shares the duplicate guard with web requests' do
    create(:stat, user: user, year: 2025, month: 1)
    headers = { 'Authorization' => "Bearer #{user.api_key}" }
    ActiveJob::Base.queue_adapter = :test
    expect do
      post users_digests_path, params: { year: 2025 }
      post api_v1_digests_path, params: { year: 2025 }, headers: headers
      expect(response).to have_http_status(:accepted)
    end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).exactly(:once)
    get api_v1_digests_path, headers: headers
    expect(response.parsed_body['digests']).to be_empty
    get api_v1_digest_path(year: 2025), headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'allows retrying a failed generation through the API' do
    create(:stat, user: user, year: 2025, month: 1)
    digest = user.digests.yearly.create!(year: 2025, generation_status: :failed)
    post api_v1_digests_path, params: { year: 2025 }, headers: { 'Authorization' => "Bearer #{user.api_key}" }
    expect(response).to have_http_status(:accepted)
    expect(digest.reload).to be_generation_queued
  end

  it 'backs up ready reports without restoring pending job state' do
    ready = create(:users_digest, user: user, year: 2024)
    user.digests.yearly.create!(year: 2025, generation_status: :queued)
    data = Users::ExportData::Digests.new(user).call
    expect(data.map { |d| d['year'] }).to eq([ready.year])
    expect(data.first).not_to have_key('generation_status')
    other = create(:user)
    Users::ImportData::Digests.new(other, [data.first.merge('generation_status' => 'queued')]).call
    expect(other.digests.sole).to be_generation_ready
  end
end
