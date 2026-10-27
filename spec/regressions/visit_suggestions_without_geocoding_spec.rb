# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit suggestions without a configured geocoder', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, :pro_plan, settings: {
             'visits_suggestions_enabled' => 'true',
      'visit_radius_meters' => 100,
      'visit_min_points' => 3,
      'visit_min_duration_minutes' => 2,
      'live_map_enabled' => false,
      'timezone' => 'Etc/UTC'
           })
  end
  let(:arrival) { 30.minutes.ago }
  let(:departure) { arrival + 4.minutes }
  let(:payloads) do
    # Made-up stationary fixes in the South Pacific, far from inhabited land.
    [0, 120, 240].map do |offset|
      {
        lonlat: 'POINT(-140.12345 -40.12345)',
        timestamp: arrival.to_i + offset,
        accuracy: 5,
        velocity: 0,
        tracker_id: 'synthetic-android'
      }
    end
  end

  around { |example| freeze_time { example.run } }

  before do
    clear_enqueued_jobs
    Visits::RealtimeDebouncer.new(user.id).clear
    Tracks::RealtimeDebouncer.new(user.id).clear
    allow(Geocoder).to receive(:search).and_return([])

    expect(Geocoding::Config.for(user).enabled?).to be(false)
    expect(user.safe_settings.visits_suggestions_enabled?).to be(true)
  end

  after do
    Visits::RealtimeDebouncer.new(user.id).clear
    Tracks::RealtimeDebouncer.new(user.id).clear
    clear_enqueued_jobs
  end

  def expect_stationary_visit
    expect(user.visits.suggested.count).to eq(1)
    visit = user.visits.suggested.first
    expect(visit.started_at.to_i).to eq(arrival.to_i)
    expect(visit.ended_at.to_i).to eq(departure.to_i)
    expect(visit.name).to be_nil
    expect(visit.place).to be_nil
    expect(visit.location_label).to eq('Unknown Location')
    expect(visit.display_name).to eq('Unknown Location')
    expect(user.places.count).to eq(0)
    expect(user.points.pluck(:geodata)).to all(eq({}))
    expect(user.points.where(visit_id: visit.id).count).to eq(3)
    expect(Geocoder).not_to have_received(:search)
  end

  it 'can detect the same stationary fixes when the worker is called directly' do
    Points::Intake.call(user_id: user.id, payloads: payloads, mode: :bulk)

    VisitSuggestingJob.perform_now(user_id: user.id, start_at: arrival, end_at: departure)

    expect_stationary_visit
  end

  it 'suggests a visit after realtime mobile points are received' do
    perform_enqueued_jobs(only: VisitSuggestingJob) do
      Points::Intake.call(user_id: user.id, payloads: payloads)
    end

    expect(user.points.count).to eq(3)
    expect_stationary_visit
  end

  it 'suggests the missed visit during the next nightly scan' do
    Points::Intake.call(user_id: user.id, payloads: payloads, mode: :bulk)
    travel 1.day

    perform_enqueued_jobs(only: VisitSuggestingJob) do
      BulkVisitsSuggestingJob.perform_now(user_ids: [user.id])
    end

    expect(user.reload.points_count).to eq(3)
    expect_stationary_visit
  end

  it 'renders an unnamed mobile suggestion in the API and timeline' do
    perform_enqueued_jobs(only: VisitSuggestingJob) do
      Points::Intake.call(user_id: user.id, payloads: payloads)
    end

    expect_stationary_visit
    visit = user.visits.suggested.first

    get "/api/v1/visits/#{visit.id}", headers: { 'Authorization' => "Bearer #{user.api_key}" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include(
      'name' => 'Unknown Location', 'display_name' => 'Unknown Location',
      'custom_name' => nil, 'place' => nil
    )

    sign_in user
    day = arrival.in_time_zone('Etc/UTC').beginning_of_day
    get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

    expect(response).to have_http_status(:ok)
    title = Nokogiri::HTML(response.body).at_css("[data-testid='visit-name-#{visit.id}']")
    expect(title&.text&.strip).to eq('Unknown Location')
  end
end
