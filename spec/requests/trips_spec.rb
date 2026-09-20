# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/trips', type: :request do
  def capture_sql(&block)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end

  let(:valid_attributes) do
    {
      name: 'Summer Vacation 2024',
      started_at: Date.tomorrow,
      ended_at: Date.tomorrow + 7.days,
      notes: 'A wonderful week-long trip'
    }
  end

  let(:invalid_attributes) do
    {
      name: '', # name can't be blank
      start_date: nil, # dates are required
      end_date: Date.yesterday # end date can't be before start date
    }
  end
  let(:user) { create(:user) }

  before do
    allow_any_instance_of(Trip).to receive(:photos_by_day).and_return({})

    sign_in user
  end

  describe 'GET /index' do
    it 'previews the plan of a trip that has no recorded path yet' do
      planned = create(:trip, user:, path: nil, distance: nil, started_at: 1.day.from_now, ended_at: 2.days.from_now)
      day = planned.planned_days.create!(date: planned.started_at.to_date, position: 1)
      day.planned_stops.create!(name: 'Uffizi', position: 1, latitude: 43.768, longitude: 11.255)

      get trips_url

      card = Nokogiri::HTML(response.body).at_css("#trip-#{planned.id}")
      expect(card.at_css('[data-trip-maplibre-preview-plan-value]')).to be_present
      expect(card.text).to include('Plan')
    end

    it 'renders a successful response' do
      get trips_url
      expect(response).to be_successful
    end

    context 'when trip path is not yet calculated' do
      let!(:trip_without_path) { create(:trip, user:, path: nil, distance: nil) }

      it 'renders a successful response with loading state' do
        get trips_url
        expect(response).to be_successful
        expect(response.body).to include('Calculating...')
      end
    end
  end

  describe 'GET /show' do
    let(:trip) { create(:trip, :with_points, user:) }

    it 'renders a successful response' do
      get trip_url(trip)

      expect(response).to be_successful
    end

    it 'does not load the unused raw point coordinate projection' do
      queries = capture_sql { get trip_url(trip) }

      expect(
        queries.none? { |sql| sql.include?('ST_Y(lonlat::geometry)') && sql.include?('"points"."battery"') }
      ).to be(true)
    end

    it 'renders the recalculate button' do
      get trip_url(trip)

      expect(response.body).to include('Recalculate')
    end

    it 'renders header edit and delete actions' do
      get trip_url(trip)

      expect(response.body).to include(edit_trip_path(trip))
      expect(response.body).to include('Delete this trip')
    end

    it 'renders a read-only itinerary for a TREK-managed trip' do
      allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
      source = create(:trip_source, user:)
      trip.update!(trip_source: source, source_identifier: '12', source_status: :active)
      day = trip.planned_days.create!(date: trip.started_at.to_date, position: 1, title: 'Arrival')
      day.planned_stops.create!(name: 'Uffizi', position: 1, transport_mode: 'walk', duration_minutes: 90)
      day.planned_day_notes.create!(position: 1, body: 'Bring the tickets', noted_at: '09:00')
      trip.planned_reservations.create!(
        planned_day: day, title: 'LH 1234', status: 'confirmed', notes: 'Online check-in'
      )
      trip.planned_reservations.create!(title: 'Train 987', location: 'Florence')
      trip.planned_accommodations.create!(
        name: 'Hotel Roma', starts_on: trip.started_at.to_date, ends_on: trip.ended_at.to_date
      )

      get trip_url(trip)

      expect(response.body).to include('Plan from TREK')
      expect(response.body).to include('Uffizi')
      expect(response.body).to include('Bring the tickets')
      expect(response.body).to include('LH 1234')
      expect(response.body).to include('Train 987')
      expect(response.body).to include('Walk')
      expect(response.body).to include('90 min')
      expect(response.body).to include('Confirmed')
      expect(response.body).to include('Hotel Roma')
    end

    it 'says when a TREK plan was synced and links back to the trip in TREK' do
      allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
      source = create(:trip_source, user:)
      trip.update!(trip_source: source, source_identifier: '12', source_status: :active,
                   source_synced_at: 5.minutes.ago)
      day = trip.planned_days.create!(date: trip.started_at.to_date, position: 1)
      day.planned_stops.create!(name: 'Uffizi', position: 1, transport_mode: 'walking')

      get trip_url(trip)

      expect(response.body).to include('Synced 5 minutes ago')
      expect(response.body).to include('href="https://trek.example.test/trips/12"')
      expect(response.body).to include('Day 1')
      expect(response.body).to include('Walking')
      expect(response.body).not_to include('Managed by TREK')
    end

    it 'keeps the trip actions above the TREK plan and lists travellers in the plan header' do
      trip.update!(source_identifier: '12', source_status: :active)
      day = trip.planned_days.create!(date: trip.started_at.to_date, position: 1)
      day.planned_stops.create!(name: 'Uffizi', position: 1)
      trip.planned_travellers.create!(name: 'Ada', owner: true)

      get trip_url(trip)
      body = response.body

      expect(body.index('data-trip-maplibre-target="replayToggleBtn"')).to be < body.index('Plan from TREK')
      expect(body.index('Plan from TREK')).to be < body.index('Ada')
      expect(body.index('Ada')).to be < body.index('Day 1')
    end

    it 'shows TREK day notes in the day note, and in the plan only when the day note differs' do
      trip.update!(source_identifier: '12', source_status: :active)
      first = trip.planned_days.create!(date: trip.started_at.to_date, position: 1, notes: 'Synced into Dawarich')
      second = trip.planned_days.create!(date: trip.started_at.to_date + 1, position: 2, notes: 'Only in the plan')
      [first, second].each { |day| day.planned_stops.create!(name: 'Uffizi', position: 1) }
      trip.notes.create!(user:, date: first.date, body: 'Synced into Dawarich',
                         source_digest: Note.body_digest('Synced into Dawarich'))
      trip.notes.create!(user:, date: second.date, body: 'My own words')

      get trip_url(trip)
      plan = response.body[%r{<section class="mb-6 rounded-lg border[\s\S]*?</section>}]

      expect(plan).not_to include('Synced into Dawarich')
      expect(plan).to include('Only in the plan')
      expect(response.body).to include('Synced into Dawarich')
    end

    it 'shows a finished trip without recorded locations as empty rather than calculating' do
      empty_trip = create(:trip, user:, path: nil, started_at: 3.days.ago, ended_at: 2.days.ago)

      get trip_url(empty_trip)

      expect(response.body).to include('No locations were recorded during this trip.')
      expect(response.body).not_to include('Trip path is being calculated...')
    end

    it 'keeps showing progress while a trip with recorded locations is calculated' do
      calculating = create(:trip, :with_points, user:, path: nil)

      get trip_url(calculating)

      expect(response.body).to include('Trip path is being calculated...')
    end

    it 'keeps a disconnected TREK itinerary visible' do
      trip.update!(source_status: :stopped)
      day = trip.planned_days.create!(date: trip.started_at.to_date, position: 1, title: 'Arrival')
      day.planned_stops.create!(name: 'Uffizi', position: 1)

      get trip_url(trip)

      expect(response.body).to include('Plan from TREK')
      expect(response.body).to include('Sync stopped')
      expect(response.body).to include('Uffizi')
    end

    it 'shows a future TREK trip as planned instead of permanently calculating its path' do
      allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
      source = create(:trip_source, user:)
      trip.update!(
        trip_source: source,
        source_identifier: '12',
        source_status: :active,
        started_at: 1.day.from_now,
        ended_at: 2.days.from_now,
        path: nil
      )

      expect { get trip_url(trip) }.not_to have_enqueued_job(Trips::CalculateAllJob)

      expect(response.body).to include('This planned trip has not started yet.')
      expect(response.body).not_to include('Trip path is being calculated...')
    end

    it 'draws the plan of a future TREK trip on the map, with stops that fly the map to them' do
      trip.update!(source_identifier: '12', source_status: :active, path: nil,
                   started_at: 1.day.from_now, ended_at: 3.days.from_now)
      day = trip.planned_days.create!(date: trip.started_at.to_date, position: 1)
      day.planned_stops.create!(name: 'Uffizi', position: 1, latitude: 43.768, longitude: 11.255)
      day.planned_stops.create!(name: 'Somewhere', position: 2)

      get trip_url(trip)
      page = Nokogiri::HTML(response.body)

      map = page.at_css('[data-testid="trip-plan-map"]')
      expect(JSON.parse(map['data-trip-maplibre-preview-plan-value'])['features'].first['properties'])
        .to include('name' => 'Uffizi', 'number' => 1)
      expect(map['data-trip-maplibre-preview-numbered-value']).to eq('true')
      expect(response.body).to include('Planned route')
      expect(page.at_css('button[data-controller="trip-plan-focus"]').text.strip).to eq('Uffizi')
      expect(page.css('button[data-controller="trip-plan-focus"]').size).to eq(1)
    end

    it 'offers the plan as a toggle over the recorded track of a past trip' do
      day = trip.planned_days.create!(date: trip.started_at.to_date, position: 1)
      day.planned_stops.create!(name: 'Uffizi', position: 1, latitude: 43.768, longitude: 11.255)

      get trip_url(trip)
      page = Nokogiri::HTML(response.body)

      expect(page.at_css('[data-testid="trip-plan-map"]')).to be_nil
      plan = page.at_css('[data-controller="trip-maplibre"]')['data-trip-maplibre-plan-value']
      expect(JSON.parse(plan)['features'].first['properties']).to include('name' => 'Uffizi')
      expect(page.at_css('[data-testid="trip-plan-toggle"]')['data-action']).to eq('click->trip-maplibre#togglePlan')
      expect(page.at_css('button[data-controller="trip-plan-focus"]').text.strip).to eq('Uffizi')
    end

    it 'offers no plan toggle for a trip without a plan' do
      get trip_url(trip)
      page = Nokogiri::HTML(response.body)

      expect(page.at_css('[data-testid="trip-plan-toggle"]')).to be_nil
      expect(page.at_css('[data-controller="trip-maplibre"]')['data-trip-maplibre-plan-value']).to be_nil
    end

    it 'keeps a disconnected future TREK trip in its planned state' do
      trip.update!(
        source_identifier: '12',
        source_status: :stopped,
        started_at: 1.day.from_now,
        ended_at: 2.days.from_now,
        path: nil
      )

      expect { get trip_url(trip) }.not_to have_enqueued_job(Trips::CalculateAllJob)

      expect(response.body).to include('This planned trip has not started yet.')
      expect(response.body).not_to include('Trip path is being calculated...')
    end

    describe 'poster studio' do
      it 'renders the studio without date controls' do
        get trip_url(trip)

        expect(response.body).to include('id="poster-studio"')
        expect(response.body).not_to include('data-poster-studio-editor-target="dateStart"')
      end

      it 'passes the trip name to the map controller' do
        get trip_url(trip)

        expect(response.body).to include("data-trip-maplibre-trip-name-value=\"#{trip.name}\"")
      end

      it 'renders an enabled poster button when the path exists' do
        get trip_url(trip)

        button = Nokogiri::HTML(response.body).at_css('[data-trip-maplibre-target="posterBtn"]')
        expect(button).to be_present
        expect(button['disabled']).to be_nil
      end

      it 'offers poster and video studios as named icons beside the other trip actions' do
        get trip_url(trip)

        page = Nokogiri::HTML(response.body)
        actions = page.at_css('[data-testid="trip-header-actions"]')
        poster = actions.at_css('[data-trip-maplibre-target="posterBtn"]')
        video = actions.at_css('[data-action="click->trip-maplibre#openVideoStudio"]')
        expect(poster['aria-label']).to eq('Create a poster of this trip')
        expect(video['aria-label']).to eq('Create a replay video of this trip')
        expect(page.css('[data-trip-maplibre-target="posterBtn"]').size).to eq(1)
        expect(page.css('[data-action="click->trip-maplibre#openVideoStudio"]').size).to eq(1)
      end

      it 'renders a disabled poster button while the path is calculating' do
        trip.update_columns(path: nil)

        get trip_url(trip)

        button = Nokogiri::HTML(response.body).at_css('[data-trip-maplibre-target="posterBtn"]')
        expect(button['disabled']).to be_present
        expect(button['title']).to eq('Available once the trip route is calculated')
      end

      it 'renders the poster gallery list' do
        create(:poster, user:)

        get trip_url(trip)

        expect(response.body).to include('poster-gallery-list')
      end
    end

    context 'with photos grouped by day' do
      let(:photo) do
        { id: 7, url: '/api/v1/photos/7/thumbnail.jpg?api_key=x&source=immich',
          source: 'immich', orientation: 'landscape' }
      end

      before do
        allow_any_instance_of(Trip).to receive(:photos_by_day)
          .and_return({ Date.new(2024, 11, 28) => [photo] })
      end

      it "renders a day's photos inside that day's collapse" do
        get trip_url(trip)

        day = Nokogiri::HTML(response.body).at_css("details[data-day-key='2024-11-28']")
        expect(day.at_css("img[src='#{photo[:url]}']")).to be_present
      end

      it 'renders photo thumbnails only inside day collapses (no flat bottom grid)' do
        get trip_url(trip)

        imgs = Nokogiri::HTML(response.body).css("img[src*='/api/v1/photos/']")
        expect(imgs).to be_present
        expect(imgs).to all(satisfy { |img| img.ancestors('details').any? })
      end
    end

    it 'computes day stats with PostGIS (no Ruby Geocoder fallback)' do
      allow(Geocoder::Calculations).to receive(:distance_between).and_call_original

      get trip_url(trip)

      expect(response).to be_successful
      expect(Geocoder::Calculations).not_to have_received(:distance_between)
    end

    it 'refreshes cached day stats when the recording gap setting changes' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      user.update!(settings: user.settings.merge('minutes_between_routes' => 60, 'timezone' => 'UTC'))
      recorded_trip = create(:trip, user:, started_at: Time.utc(2026, 1, 1, 23), ended_at: Time.utc(2026, 1, 3))
      midnight = Time.utc(2026, 1, 2)
      { 'phone' => [-10, 30, 35, 40], 'watch' => [5, 10] }.each do |device, minutes|
        minutes.each do |minute|
          create(:point, user:, tracker_id: device, timestamp: (midnight + minute.minutes).to_i,
                         latitude: 52, longitude: 13 + minute * 0.001)
        end
      end

      get trip_url(recorded_trip)

      day = Nokogiri::HTML(response.body).at_css("details[data-day-key='2026-01-02'] summary")
      expect(day.text).to include('00:30')
      expect(day.text).not_to include('00:05')

      user.update!(settings: user.settings.merge('minutes_between_routes' => 10))
      get trip_url(recorded_trip)

      day = Nokogiri::HTML(response.body).at_css("details[data-day-key='2026-01-02'] summary")
      expect(day.text).to include('00:05')
      expect(day.text).not_to include('00:30')
    end

    context 'when the user timezone is not UTC' do
      before { user.update!(settings: user.settings.merge('timezone' => 'Europe/Berlin')) }

      let(:boundary_trip) do
        create(:trip, user:, started_at: Time.utc(2025, 1, 15), ended_at: Time.utc(2025, 1, 16, 23, 59, 59))
      end

      it 'buckets a point just after local midnight into its correct local day' do
        create(:point, user:, timestamp: Time.utc(2025, 1, 15, 12, 0).to_i, latitude: 52.0, longitude: 13.0)
        create(:point, user:, timestamp: Time.utc(2025, 1, 15, 23, 30).to_i, latitude: 52.6, longitude: 13.4)

        get trip_url(boundary_trip)

        day = Nokogiri::HTML(response.body).at_css("details[data-day-key='2025-01-16']")
        expect(day.text).to include('00:30')
        expect(day.text).not_to include('No data')
      end

      it 'renders successfully when the timezone is a non-IANA ActiveSupport name' do
        user.update!(settings: user.settings.merge('timezone' => 'Berlin'))
        create(:point, user:, timestamp: Time.utc(2025, 1, 15, 12, 0).to_i, latitude: 52.0, longitude: 13.0)

        get trip_url(boundary_trip)

        expect(response).to be_successful
      end
    end
  end

  describe 'GET /new' do
    it 'renders a successful response' do
      get new_trip_url

      expect(response).to be_successful
    end

    it 'cancels back to the trips list' do
      get new_trip_url

      form = Nokogiri::HTML(response.body).at_css("form[action='#{trips_path}']")
      expect(form.at_css("a[href='#{trips_path}']").text.strip).to eq('Cancel')
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'redirects to the root path' do
        get new_trip_url

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Your account is not active.')
      end
    end
  end

  describe 'GET /edit' do
    let(:trip) { create(:trip, :with_points, user:) }

    it 'renders a successful response' do
      get edit_trip_url(trip)

      expect(response).to be_successful
    end

    it 'does not load the unused raw point coordinate projection' do
      queries = capture_sql { get edit_trip_url(trip) }

      expect(
        queries.none? { |sql| sql.include?('ST_Y(lonlat::geometry)') && sql.include?('"points"."battery"') }
      ).to be(true)
    end

    it 'ends the form with saving and cancelling back to the trip' do
      get edit_trip_url(trip)

      form = Nokogiri::HTML(response.body).at_css("form[action='#{trip_path(trip)}']")
      expect(form.at_css('input[type=submit].btn.btn-primary')).to be_present
      expect(form.at_css("a[href='#{trip_path(trip)}']").text.strip).to eq('Cancel')
    end

    it 'keeps the name and dates of a TREK-managed trip read-only and says where to change them' do
      allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
      trip.update!(trip_source: create(:trip_source, user:), source_identifier: '12', source_status: :active)

      get edit_trip_url(trip)
      page = Nokogiri::HTML(response.body)

      %w[trip_name trip_started_at trip_ended_at].each do |field|
        expect(page.at_css("##{field}")['readonly']).to be_present
      end
      expect(response.body).to include('https://trek.example.test/trips/12')
    end

    it 'lets a stopped TREK trip be edited freely' do
      trip.update!(source_identifier: '12', source_status: :stopped)

      get edit_trip_url(trip)

      expect(Nokogiri::HTML(response.body).at_css('#trip_name')['readonly']).to be_nil
    end
  end

  describe 'POST /create' do
    context 'with valid parameters' do
      it 'creates a new Trip' do
        expect do
          post trips_url, params: { trip: valid_attributes }
        end.to change(Trip, :count).by(1)
      end

      it 'redirects to the created trip' do
        post trips_url, params: { trip: valid_attributes }
        expect(response).to redirect_to(trip_url(Trip.last))
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'redirects to the root path' do
          post trips_url, params: { trip: valid_attributes }

          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq('Your account is not active.')
        end
      end
    end

    context 'with invalid parameters' do
      it 'does not create a new Trip' do
        expect do
          post trips_url, params: { trip: invalid_attributes }
        end.to change(Trip, :count).by(0)
      end

      it "renders a response with 422 status (i.e. to display the 'new' template)" do
        post trips_url, params: { trip: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PATCH /update' do
    context 'with valid parameters' do
      let(:new_attributes) do
        {
          name: 'Updated Trip Name',
          description: 'Changed trip notes'
        }
      end
      let(:trip) { create(:trip, :with_points, user:) }

      it 'updates the requested trip' do
        patch trip_url(trip), params: { trip: new_attributes }
        trip.reload

        expect(trip.name).to eq('Updated Trip Name')
        expect(trip.description.body.to_plain_text).to eq('Changed trip notes')
        expect(trip.description).to be_an(ActionText::RichText)
      end

      it 'redirects to the trip' do
        patch trip_url(trip), params: { trip: new_attributes }
        trip.reload

        expect(response).to redirect_to(trip_url(trip))
      end
    end

    context 'with invalid parameters' do
      let(:trip) { create(:trip, :with_points, user:) }

      it 'renders a response with 422 status' do
        patch trip_url(trip), params: { trip: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /destroy' do
    let!(:trip) { create(:trip, :with_points, user:) }

    it 'destroys the requested trip' do
      expect do
        delete trip_url(trip)
      end.to change(Trip, :count).by(-1)
    end

    it 'redirects to the trips list' do
      delete trip_url(trip)

      expect(response).to redirect_to(trips_url)
    end
  end
end
