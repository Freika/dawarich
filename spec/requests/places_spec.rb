# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/places', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      get places_url

      expect(response).to be_successful
    end

    it 'can show only unconfirmed suggested Places' do
      suggested = create(:place, user:, source: :photon, name: 'Needs Review')
      create(:visit, user:, place: suggested, status: :suggested)
      create(:place, user:, source: :manual, name: 'My Home')

      get places_url(filter: 'unconfirmed')

      expect(response.body).to include('Needs Review')
      expect(response.body).not_to include('My Home')
    end

    it 'offers a direct confirmation action for unconfirmed Places' do
      suggested = create(:place, user:, source: :photon, name: 'Needs Review')
      create(:visit, user:, place: suggested, status: :suggested)

      get places_url(filter: 'unconfirmed')

      expect(response.body).to include(confirm_place_path(suggested))
      expect(response.body).to include('Confirm')
    end

    it 'links each Place to its details, where it can be merged' do
      place = create(:place, user:, name: 'My Home')

      get places_url

      links = Nokogiri::HTML(response.body).css("a[href='#{place_path(place)}']").map { |link| link.text.strip }
      expect(links).to include('My Home')
    end
  end

  describe 'PATCH /places/:id/confirm' do
    it 'promotes a suggested Place into the user-owned catalogue' do
      place = create(:place, user:, source: :photon, name: 'Neighbourhood cafe')
      create(:visit, user:, place:, status: :suggested)

      patch confirm_place_url(place), params: { filter: 'unconfirmed' }

      expect(response).to redirect_to(places_url(filter: 'unconfirmed'))
      expect(place.reload).to have_attributes(source: 'manual')
      expect(place).to be_name_locked
      expect(Place.unconfirmed_for(user)).not_to include(place)
    end

    it 'does not lock the placeholder name so geocoding can still rename the Place' do
      place = create(:place, user:, source: :photon, name: Place::DEFAULT_NAME)

      patch confirm_place_url(place)

      expect(place.reload).to have_attributes(source: 'manual', name_locked_at: nil)
    end

    it "does not confirm another user's Place" do
      other_place = create(:place, user: create(:user), source: :photon)

      patch confirm_place_url(other_place)

      expect(response).to have_http_status(:not_found)
      expect(other_place.reload.source).to eq('photon')
    end
  end

  describe 'POST /create' do
    context 'with turbo_stream format' do
      let(:valid_params) do
        { place: { name: 'Coffee Shop', latitude: 52.52, longitude: 13.405, source: 'manual', visit_radius: 125 } }
      end

      context 'with valid params' do
        it 'creates a new place' do
          expect do
            post places_url, params: valid_params, as: :turbo_stream
          end.to change(Place, :count).by(1)
        end

        it 'reattributes Suggested Visits after explicit user creation' do
          expect do
            post places_url, params: valid_params, as: :turbo_stream
          end.to have_enqueued_job(Places::ReattributeSuggestedVisitsJob)
        end

        it 'stores and returns the visit radius' do
          post places_url, params: valid_params, as: :turbo_stream

          expect(Place.last.visit_radius).to eq(125)
          expect(response.body).to include('visit_radius&quot;:125')
        end

        it 'returns turbo_stream replacing place-creation-data with flash' do
          post places_url, params: valid_params, as: :turbo_stream

          expect_turbo_stream_response
          expect_turbo_stream_action('replace', 'place-creation-data')
          expect_flash_stream('Place created successfully!')
        end

        it 'includes created flag in response' do
          post places_url, params: valid_params, as: :turbo_stream

          expect(response.body).to include('data-created="true"')
        end

        it 'associates tags when provided' do
          tag1 = create(:tag, user:)
          params_with_tags = { place: { name: 'Tagged Place', latitude: 52.52, longitude: 13.405, tag_ids: [tag1.id] } }

          post places_url, params: params_with_tags, as: :turbo_stream

          expect(Place.last.tags).to include(tag1)
        end

        it 'creates a full Place from a Visit and attaches it atomically' do
          legacy_area = create(:area, user:)
          visit = create(:visit, user:, area: legacy_area, status: :suggested, location_label: 'Corner cafe')

          post places_url,
               params: valid_params.merge(visit_id: visit.id),
               as: :turbo_stream

          expect(response).to have_http_status(:ok)
          expect(visit.reload).to have_attributes(
            place_id: Place.last.id,
            area_id: nil,
            location_label: 'Coffee Shop',
            status: 'confirmed'
          )
          expect(response.body).to include("data-visit-id=\"#{visit.id}\"")
        end

        it 'drops a Visit name that only repeated its legacy Area' do
          legacy_area = create(:area, user:, name: 'Old corner')
          visit = create(:visit, user:, area: legacy_area, name: 'Old corner', location_label: 'Old corner')

          post places_url, params: valid_params.merge(visit_id: visit.id), as: :turbo_stream

          expect(visit.reload.name).to be_nil
          expect(visit.display_name).to eq('Coffee Shop')
        end

        it 'does not create a Place when the Visit belongs to another user' do
          other_visit = create(:visit, user: create(:user))

          expect do
            post places_url,
                 params: valid_params.merge(visit_id: other_visit.id),
                 as: :turbo_stream
          end.not_to change(Place, :count)

          expect(response).to have_http_status(:not_found)
        end
      end

      context 'with invalid params' do
        let(:invalid_params) { { place: { name: '', latitude: 52.52, longitude: 13.405 } } }

        it 'does not create a place' do
          expect do
            post places_url, params: invalid_params, as: :turbo_stream
          end.not_to change(Place, :count)
        end

        it 'returns turbo_stream flash error' do
          post places_url, params: invalid_params, as: :turbo_stream

          expect_turbo_stream_response
          expect_flash_stream
        end
      end
    end
  end

  describe 'PATCH /update' do
    let!(:place) { create(:place, user:) }

    context 'with turbo_stream format' do
      it 'updates the place and returns turbo_stream' do
        patch place_url(place), params: { place: { name: 'Updated Name', visit_radius: 90 } }, as: :turbo_stream

        expect(place.reload.name).to eq('Updated Name')
        expect(place.visit_radius).to eq(90)
        expect_turbo_stream_response
        expect_turbo_stream_action('replace', 'place-creation-data')
        expect_flash_stream('Place updated successfully!')
      end

      it 'clears the last tag when the map modal submits with every tag unchecked' do
        place.tags << create(:tag, user:)
        get map_v2_url
        document = Nokogiri::HTML(response.body)
        hidden = document.at_css('input[type="hidden"][name="place[tag_ids][]"]')
        submitted_tags = hidden ? [hidden['value']] : nil
        attributes = { name: place.name }
        attributes[:tag_ids] = submitted_tags if submitted_tags

        patch place_url(place), params: { place: attributes }, as: :turbo_stream

        expect(response).to have_http_status(:ok)
        expect(place.reload.tags).to be_empty

        post places_url,
             params: { place: { name: 'Untagged Cafe', latitude: 52.52, longitude: 13.405, tag_ids: submitted_tags } },
             as: :turbo_stream

        expect(response).to have_http_status(:ok)
        expect(user.places.find_by!(name: 'Untagged Cafe').tags).to be_empty
      end

      it 'includes updated flag in response' do
        patch place_url(place), params: { place: { name: 'Updated' } }, as: :turbo_stream

        expect(response.body).to include('data-updated="true"')
      end

      it 'excludes tombstoned visits from the serialized visits_count' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        create(:visit, place:, user:,
                       started_at: base_time, ended_at: base_time + 30.minutes)
        create(:visit, place:, user:, deleted_at: 1.day.ago,
                       started_at: base_time + 1.hour, ended_at: base_time + 90.minutes)

        patch place_url(place), params: { place: { name: 'Renamed' } }, as: :turbo_stream

        expect(response.body).to include('visits_count&quot;:1')
      end

      it 'returns turbo_stream flash error with invalid params' do
        patch place_url(place), params: { place: { name: '' } }, as: :turbo_stream

        expect_turbo_stream_response
        expect_flash_stream
      end
    end
  end

  describe 'GET /nearby' do
    let(:geocoder_result) do
      double(
        'result',
        data: {
          'properties' => {
            'name' => 'Test Place',
            'city' => 'Berlin',
            'country' => 'Germany',
            'street' => 'Test Street',
            'housenumber' => '1',
            'osm_id' => 123
          },
          'geometry' => { 'coordinates' => [13.405, 52.52] }
        }
      )
    end

    it 'returns nearby places partial with place cards' do
      configure_instance_geocoding
      allow(Geocoder).to receive(:search).and_return([geocoder_result])

      get nearby_places_url, params: { latitude: 52.52, longitude: 13.405 }

      expect(response).to be_successful
      expect(response.body).to include('data-place-name="Test Place"')
    end

    it 'returns bad request when coordinates are missing' do
      get nearby_places_url

      expect(response).to have_http_status(:bad_request)
    end

    it 'renders no results message when geocoder returns empty' do
      configure_instance_geocoding
      allow(Geocoder).to receive(:search).and_return([])

      get nearby_places_url, params: { latitude: 52.52, longitude: 13.405 }

      expect(response).to be_successful
      expect(response.body).to include('No nearby places found')
    end

    it 'renders no results when the instance has no geocoding provider' do
      get nearby_places_url, params: { latitude: 52.52, longitude: 13.405 }

      expect(response).to be_successful
      expect(response.body).to include('No nearby places found')
    end
  end

  describe 'DELETE /destroy' do
    let!(:place) { create(:place, user:) }
    let!(:visit) { create(:visit, place:, user:) }

    it 'destroys the requested place' do
      expect do
        delete place_url(place)
      end.to change(Place, :count).by(-1)
    end

    it 'redirects to the places list' do
      delete place_url(place)

      expect(response).to redirect_to(places_url)
    end

    it 'deletes mapped legacy Area shells so the Place cannot be recreated' do
      area = create(:area, user:)
      LegacyAreaPlaceMapping.create!(area:, place:)

      delete place_url(place)

      expect(Area.exists?(area.id)).to be(false)
      expect(LegacyAreaPlaceMapping.exists?(area_id: area.id)).to be(false)
      expect(Visit.exists?(visit.id)).to be(true)
    end
  end

  describe 'POST /places/:id/merge' do
    let!(:survivor) { create(:place, user:, name: 'Home') }
    let!(:duplicate) { create(:place, user:, name: 'My Home') }

    it 'merges the duplicate into the selected survivor' do
      visit = create(:visit, user:, place: duplicate, status: :confirmed)

      post merge_place_url(survivor),
           params: { duplicate_place_id: duplicate.id },
           as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(visit.reload.place).to eq(survivor)
      expect(Place.exists?(duplicate.id)).to be(false)
      expect_turbo_stream_action('update', 'place-drawer')
    end

    it 'relays a merged survivor and the removed duplicate to the map panel' do
      tag = create(:tag, user:)
      duplicate.tags << tag

      post merge_place_url(survivor), params: { duplicate_place_id: duplicate.id, map_panel: '1' },
                                      headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(survivor.reload.tags).to include(tag)
      expect_turbo_stream_action('replace', 'place-creation-data')
      expect(response.body).to include("data-removed-id=\"#{duplicate.id}\"", 'data-updated="true"')
    end

    it 'does not merge another users Place' do
      other_place = create(:place, user: create(:user))

      expect do
        post merge_place_url(survivor),
             params: { duplicate_place_id: other_place.id },
             as: :turbo_stream
      end.not_to change(Place, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'does not merge a Place into itself' do
      expect do
        post merge_place_url(survivor), params: { duplicate_place_id: survivor.id }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "does not merge into another user's survivor Place" do
      other_survivor = create(:place, user: create(:user))

      expect do
        post merge_place_url(other_survivor), params: { duplicate_place_id: duplicate.id }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'reports a timestamp conflict without changing either Place' do
      started_at = Time.zone.parse('2026-09-01 12:00:00')
      create(:visit, user:, place: survivor, started_at:)
      duplicate_visit = create(:visit, user:, place: duplicate, started_at:)

      expect do
        post merge_place_url(survivor), params: { duplicate_place_id: duplicate.id }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Visit ##{duplicate_visit.id}")
      expect(response.body).to include('both start at September 01, 2026')
      expect(duplicate_visit.reload.place).to eq(duplicate)
    end
  end

  describe 'GET /show' do
    let!(:place) do
      create(:place, user:, name: 'Test Cafe', city: 'Berlin', country: 'Germany', source: :manual)
    end

    context 'when authenticated' do
      it 'returns a successful response' do
        get place_url(place)

        expect(response).to have_http_status(:ok)
      end

      it 'wraps the body in the place-drawer turbo-frame' do
        get place_url(place)

        expect(response.body).to include('turbo-frame')
        expect(response.body).to include('id="place-drawer"')
      end

      it 'renders inside the application layout for a direct visit' do
        get place_url(place)

        expect(response.body).to include('<html')
      end

      it 'deletes the Place from the drawer through its member route' do
        get place_url(place)

        delete_method = "form[action='#{place_path(place)}'] input[name='_method'][value='delete']"
        expect(Nokogiri::HTML(response.body).at_css(delete_method)).to be_present
      end

      it 'renders the merge search without missing translations' do
        get place_url(place)

        expect(response.body).not_to include('translation_missing')
      end

      it 'renders the place name, city, and country' do
        get place_url(place)

        expect(response.body).to include('Test Cafe')
        expect(response.body).to include('Berlin')
        expect(response.body).to include('Germany')
      end

      it 'searches a bounded merge candidate list by name with location context' do
        create(:place, user:, name: 'Nearby candidate', latitude: place.lat, longitude: place.lon)
        distant = create(:place, user:, name: 'Distant duplicate', latitude: 48.8566, longitude: 2.3522)
        create(:place, user:, name: 'Unrelated place', latitude: 48.8566, longitude: 2.3522)

        get place_url(place), params: { merge_query: 'Distant' }

        expect(response.body).to include('Distant duplicate')
        expect(response.body).to include(distant.lat.to_s, distant.lon.to_s)
        expect(response.body).not_to include('Nearby candidate', 'Unrelated place')
      end

      it 'shows merge candidate distances in the distance unit the user chose' do
        user.update!(settings: user.settings.merge('maps' => { 'distance_unit' => 'mi' }))
        create(:place, user:, name: 'Distant duplicate', latitude: 48.8566, longitude: 2.3522)

        get place_url(place), params: { merge_query: 'Distant' }

        option = Nokogiri::HTML(response.body).css('select#duplicate_place_id option').last.text
        expect(option).to match(/Distant duplicate · [\d,.]+ mi ·/)
      end

      it 'shows an empty state when no merge candidates match the search' do
        get place_url(place), params: { merge_query: 'Missing place' }

        expect(response.body).to include(I18n.t('places.drawer.no_matching_places'))
      end

      it 'labels merge search and selection controls for assistive technology' do
        create(:place, user: user, name: 'Candidate', latitude: place.lat, longitude: place.lon)

        get place_url(place)

        document = Nokogiri::HTML(response.body)
        expect(document.at_css('label[for="merge_query"]')).to be_present
        expect(document.at_css('label[for="duplicate_place_id"]')).to be_present
      end

      it 'renders the total visit count' do
        create_list(:visit, 3, place:, user:, duration: 60)

        get place_url(place)

        expect(response.body).to include('3 visits').or include('>3<')
      end

      it 'shows total dwell hours based on MINUTES column' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        3.times do |i|
          create(
            :visit,
            place:,
            user:,
            duration: 60,
            started_at: base_time + i.days,
            ended_at: base_time + i.days + 1.hour
          )
        end

        get place_url(place)

        # 3 visits * 60 minutes = 180 minutes = 3.0 hours
        expect(response.body).to include('3.0')
      end

      it 'shows average dwell formatted as Xh Ym' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        [90, 90].each_with_index do |duration, i|
          create(
            :visit,
            place:,
            user:,
            duration: duration,
            started_at: base_time + i.days,
            ended_at: base_time + i.days + duration.minutes
          )
        end

        get place_url(place)

        # avg = 90 min = 1h 30m
        expect(response.body).to include('1h 30m')
      end

      it 'hides tombstoned visits from the recent-visits list' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        create(:visit, place:, user:, name: 'Living Visit',
                       started_at: base_time, ended_at: base_time + 30.minutes)
        create(:visit, place:, user:, name: 'Ghost Visit', deleted_at: 1.day.ago,
                       started_at: base_time + 1.hour, ended_at: base_time + 90.minutes)

        get place_url(place)

        expect(response.body).to include('Living Visit')
        expect(response.body).not_to include('Ghost Visit')
      end

      it 'lists up to 5 most recent visits ordered by started_at DESC' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        7.times do |i|
          create(
            :visit,
            place:,
            user:,
            name: "Visit #{i}",
            duration: 30,
            started_at: base_time + i.hours,
            ended_at: base_time + i.hours + 30.minutes
          )
        end

        get place_url(place)

        # Most recent is Visit 6; oldest two (0, 1) should not appear in the body
        # of the drawer's recent-visits list
        expect(response.body.scan(/Visit \d/).size).to be <= 5
        expect(response.body).to include('Visit 6')
        expect(response.body).not_to include('Visit 0')
      end

      it 'does not eagerly load every point belonging to the place visits' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        visits_for_place = []
        10.times do |i|
          v = create(
            :visit,
            place:,
            user:,
            name: "Eager Visit #{i}",
            duration: 30,
            started_at: base_time + i.hours,
            ended_at: base_time + i.hours + 30.minutes
          )
          visits_for_place << v
          create_list(:point, 5, user: user, visit: v)
        end

        point_select_count = 0
        sub = lambda do |_name, _start, _finish, _id, payload|
          next if payload[:name].in?(%w[SCHEMA TRANSACTION])

          point_select_count += 1 if payload[:sql].to_s =~ /FROM "points".*"visit_id" IN/i
        end

        ActiveSupport::Notifications.subscribed(sub, 'sql.active_record') do
          get place_url(place)
        end

        expect(response).to have_http_status(:ok)
        expect(point_select_count).to eq(0),
                                      'Expected no eager-loaded SELECT FROM points ' \
                                      "WHERE visit_id IN(...), but found #{point_select_count}."
      end
    end

    context 'when unauthenticated' do
      before { sign_out user }

      it 'redirects to the sign-in page' do
        get place_url(place)

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/users/sign_in')
      end
    end

    context "when accessing another user's place" do
      let(:other_user) { create(:user) }
      let!(:other_place) { create(:place, user: other_user) }

      it 'returns 404' do
        get place_url(other_place)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PATCH /update from drawer frame' do
    let!(:place) { create(:place, user:, name: 'Drawer Place') }

    it 'returns a turbo_stream that refreshes the place-drawer frame in place' do
      patch place_url(place),
            params: { place: { note: 'Updated note' } },
            headers: { 'Turbo-Frame' => 'place-drawer' },
            as: :turbo_stream

      expect(place.reload.note).to eq('Updated note')
      expect_turbo_stream_response
      expect_turbo_stream_action('update', 'place-drawer')
    end

    it 'turns enter and leave notifications on and shows the switch on' do
      patch place_url(place),
            params: { place: { geofence: '1' } },
            headers: { 'Turbo-Frame' => 'place-drawer' },
            as: :turbo_stream

      expect(place.reload).to be_geofence
      toggle = Nokogiri::HTML(response.body).at_css('[data-testid="place-geofence-toggle"]')
      expect(toggle['checked']).to eq('checked')
    end
  end

  describe 'name locking' do
    let(:user) { create(:user) }

    before { sign_in user }

    it 'locks the name of a place the user creates by hand' do
      post places_path, params: { place: { name: "Mum's house", latitude: 51.3402, longitude: 12.3712 } },
                        as: :turbo_stream

      expect(user.places.last).to be_name_locked
    end

    it 'shows a lock indicator on the drawer for a locked place' do
      place = create(:place, user: user, name: Place::DEFAULT_NAME)
      place.update!(name: "Mum's house")

      get place_path(place)

      expect(response.body).to include('place-name-lock')
    end

    it 'shows the lock in the drawer response right after a rename' do
      place = create(:place, user: user, name: Place::DEFAULT_NAME)

      patch place_path(place), params: { place: { name: "Mum's house" } },
                               headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream

      expect(response.body).to include('place-name-lock', 'name_locked&quot;:true')
    end

    it 'drops the lock from the drawer when the name is reset to the default' do
      place = create(:place, user: user, name: Place::DEFAULT_NAME)
      place.update!(name: "Mum's house")

      patch place_path(place), params: { place: { name: Place::DEFAULT_NAME } },
                               headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream

      expect(place.reload).not_to be_name_locked
      expect(response.body).not_to include('place-name-lock')
    end

    it 'shows no lock indicator for an auto-named place' do
      place = create(:place, user: user, name: Place::DEFAULT_NAME)

      get place_path(place)

      expect(response.body).not_to include('place-name-lock')
    end
  end

  it 'accepts archive and unarchive through web Place parameters', :archive do
    place = create(:place, user:)

    patch place_url(place), params: { place: { archived: '1' } }, as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect_turbo_stream_action('replace', 'place-creation-data')
    expect(place.reload).to be_archived
    archived_data = Nokogiri::HTML(response.body).at_css('#place-creation-data')['data-place']
    expect(JSON.parse(archived_data)['archived']).to be(true)

    patch place_url(place), params: { place: { archived: '0' } }, as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect_turbo_stream_action('replace', 'place-creation-data')
    expect(place.reload).not_to be_archived
    restored_data = Nokogiri::HTML(response.body).at_css('#place-creation-data')['data-place']
    expect(JSON.parse(restored_data)['archived']).to be(false)
  end

  describe 'the shared Place editor' do
    let!(:place) { create(:place, user:, name: Place::DEFAULT_NAME) }

    it 'renders editable name tags and notes with map editing and counted delete consequences' do
      privacy_tag = create(:tag, :privacy_zone, user:, name: 'Private home')
      place.tags << privacy_tag
      create(:visit, user:, place:)
      create(:visit, user:, place:, deleted_at: 1.day.ago)
      place.update!(geofence: true)
      create(:webhook, user:, place_ids: [place.id])
      create(:webhook, user: create(:user)).update_columns(place_ids: [place.id])

      get place_url(place)

      document = Nokogiri::HTML(response.body)
      expect(document.at_css('input[name="place[name]"]')).to be_present
      expect(document.at_css('input[type="hidden"][name="place[tag_ids][]"]')['value']).to eq('')
      expect(document.at_css('input[type="checkbox"][name="place[tag_ids][]"]')['checked']).to eq('checked')
      expect(document.at_css('textarea[name="place[note]"]')).to be_present
      expect(document.at_css('[data-place-editor-target="mapLink"]')['href']).to eq(map_v2_path(place_id: place.id,
                                                                                                edit: 1))
      confirmation = document.at_css('.place-drawer__action--delete')['data-turbo-confirm']
      expect(confirmation).to include('Active visits: 1', 'Private home', 'Webhooks that will drop this place: 1',
                                      'geofence events', 'location label')
    end

    it 'saves the editor without JavaScript and locks a rename while clearing tags' do
      place.tags << create(:tag, user:)

      patch place_url(place), params: { place: { name: 'New home', note: 'My note', tag_ids: [''] } }

      expect(response).to redirect_to(place_url(place))
      expect(place.reload).to be_name_locked
      expect(place).to have_attributes(name: 'New home', note: 'My note')
      expect(place.tags).to be_empty
    end

    it 'writes a map move and radius to decimal coordinates enqueues reattribution and relays the saved feature' do
      expect do
        patch place_url(place), params: { place: { latitude: 51.1, longitude: 12.2, visit_radius: 123 } },
                                headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream
      end.to have_enqueued_job(Places::ReattributeSuggestedVisitsJob).with(user.id, place.id)

      expect(place.reload).to have_attributes(latitude: 51.1, longitude: 12.2, visit_radius: 123)
      expect([place.lonlat.x, place.lonlat.y]).to eq([12.2, 51.1])
      expect_turbo_stream_action('update', 'place-drawer')
      expect_turbo_stream_action('replace', 'place-creation-data')
      expect(response.body).to include('data-updated="true"', '123')
    end

    it 'renders invalid radius errors in the editor without saving or relaying a feature' do
      original_radius = place.visit_radius
      patch place_url(place), params: { place: { visit_radius: Place::MAX_VISIT_RADIUS + 1 } },
                              headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(place.reload.visit_radius).to eq(original_radius)
      expect_turbo_stream_action('update', 'place-drawer')
      expect(response.body).to include('role="alert"', '50000')
      expect(response.body).not_to include('target="place-creation-data"')
    end

    it 'renders invalid HTML editor input inline with the attempted name' do
      patch place_url(place), params: { place: { name: '', visit_radius: 0 } }

      expect(response).to have_http_status(:unprocessable_content)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('input[name="place[name]"]')['value']).to be_blank
      expect(document.at_css('[role="alert"]')).to be_present
    end

    it 'relays cleared tags from a drawer save and retains the geofence toggle' do
      place.tags << create(:tag, user:)
      patch place_url(place), params: { place: { tag_ids: [''], geofence: '1' } },
                              headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream

      expect(place.reload.tags).to be_empty
      expect(place).to be_geofence
      expect(response.body).to include('tags&quot;:[]', 'data-updated="true"')
      expect_turbo_stream_action('update', 'place-drawer')
    end

    it 'deletes from the map panel with a removal relay and success flash while keeping visits' do
      visit = create(:visit, user:, place:)
      delete place_url(place), params: { map_panel: '1' }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(Place.exists?(place.id)).to be(false)
      expect(visit.reload.place_id).to be_nil
      expect(visit.location_label).to eq(place.name)
      expect_turbo_stream_action('replace', 'place-creation-data')
      expect(response.body).to include("data-deleted-id=\"#{place.id}\"")
      expect_flash_stream
    end
  end
end
