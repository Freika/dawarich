# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/visits', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET /visits (retired)' do
    it 'no longer routes to VisitsController#index' do
      expect { get '/visits' }.not_to raise_error
      # The retired route now redirects (see visits_redirect_spec).
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'PATCH /bulk_update' do
    let!(:suggested_visits) { create_list(:visit, 3, user:, status: :suggested) }

    it 'confirms all suggested visits' do
      patch bulk_update_visits_url, params: { status: 'confirmed', source_status: 'suggested' }

      expect(suggested_visits.each(&:reload).map(&:status)).to all(eq('confirmed'))
      expect(response).to have_http_status(:found)
      expect(response.location).to include('/map')
      expect(response.location).to include('panel=timeline')
    end

    it 'declines all suggested visits' do
      patch bulk_update_visits_url, params: { status: 'declined', source_status: 'suggested' }

      expect(suggested_visits.each(&:reload).map(&:status)).to all(eq('declined'))
      expect(response).to have_http_status(:found)
      expect(response.location).to include('/map')
    end

    it 'does not affect visits of other users' do
      other_user = create(:user)
      other_visit = create(:visit, user: other_user, status: :suggested)

      patch bulk_update_visits_url, params: { status: 'confirmed', source_status: 'suggested' }

      expect(other_visit.reload.status).to eq('suggested')
    end

    context 'with date param (TZ-aware scoping)' do
      let(:tz) { 'Europe/Berlin' }

      before do
        user.settings ||= {}
        user.settings['timezone'] = tz
        user.save!

        Visit.delete_all

        # Visit on 2026-04-22 Berlin local (22:00 CEST = 20:00 UTC)
        @visit_on_22 = create(:visit, user: user, status: :suggested,
                                      started_at: Time.find_zone(tz).local(2026, 4, 22, 22, 0),
                                      ended_at: Time.find_zone(tz).local(2026, 4, 22, 23, 0))
        # Visit on 2026-04-23 Berlin local (01:00 CEST = 23:00 UTC on 04-22)
        @visit_on_23 = create(:visit, user: user, status: :suggested,
                                      started_at: Time.find_zone(tz).local(2026, 4, 23, 1, 0),
                                      ended_at: Time.find_zone(tz).local(2026, 4, 23, 2, 0))
      end

      it 'only updates visits within the user-local day' do
        patch bulk_update_visits_url,
              params: { status: 'confirmed', source_status: 'suggested', date: '2026-04-22' }

        expect(@visit_on_22.reload.status).to eq('confirmed')
        expect(@visit_on_23.reload.status).to eq('suggested')
      end

      it 'handles DST spring-forward boundary correctly (Europe/Berlin 2026-03-29)' do
        Visit.delete_all

        # 2026-03-29 is the DST spring-forward day in Europe/Berlin (02:00 -> 03:00)
        # Pre-DST: 01:30 Berlin CET = 00:30 UTC
        pre_dst = create(:visit, user: user, status: :suggested,
                                 started_at: Time.find_zone(tz).local(2026, 3, 29, 1, 30),
                                 ended_at: Time.find_zone(tz).local(2026, 3, 29, 1, 45))
        # Post-DST: 04:00 Berlin CEST = 02:00 UTC
        post_dst = create(:visit, user: user, status: :suggested,
                                  started_at: Time.find_zone(tz).local(2026, 3, 29, 4, 0),
                                  ended_at: Time.find_zone(tz).local(2026, 3, 29, 5, 0))
        # Next day: 2026-03-30 00:30 Berlin CEST = 2026-03-29 22:30 UTC
        next_day = create(:visit, user: user, status: :suggested,
                                  started_at: Time.find_zone(tz).local(2026, 3, 30, 0, 30),
                                  ended_at: Time.find_zone(tz).local(2026, 3, 30, 1, 0))

        patch bulk_update_visits_url,
              params: { status: 'confirmed', source_status: 'suggested', date: '2026-03-29' }

        expect(pre_dst.reload.status).to eq('confirmed')
        expect(post_dst.reload.status).to eq('confirmed')
        expect(next_day.reload.status).to eq('suggested')
      end
    end
  end

  describe 'PATCH /update' do
    context 'with valid parameters' do
      let(:visit) { create(:visit, user:, status: :suggested) }

      it 'confirms the requested visit' do
        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(visit.reload.status).to eq('confirmed')
      end

      it 'rejects the requested visit' do
        patch visit_url(visit), params: { visit: { status: :declined } }

        expect(visit.reload.status).to eq('declined')
      end

      it 'auto-names the visit from suggested place when confirming without name change' do
        place = create(:place, user:, name: 'Central Park')
        create(:place_visit, visit:, place:)

        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(visit.reload.name).to eq('Central Park')
      end

      it 'keeps the original name when confirming if no suggested place exists' do
        visit.update!(name: 'My Visit')

        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(visit.reload.name).to eq('My Visit')
      end

      it 'keeps the original name when a blank name is submitted (no 422)' do
        visit.update!(name: 'Original Name')

        patch visit_url(visit), params: { visit: { name: '  ' } }

        expect(response).not_to have_http_status(:unprocessable_content)
        expect(visit.reload.name).to eq('Original Name')
      end
    end

    context 'with turbo_stream format' do
      let(:visit) { create(:visit, user:, status: :suggested) }

      # All successful updates replace the whole `visit_entry_<id>` row so
      # status / name / picker state stay consistent with the rendered payload.
      it 'replaces the visit_entry row on status change' do
        patch visit_url(visit), params: { visit: { status: :confirmed } }, as: :turbo_stream

        expect(visit.reload.status).to eq('confirmed')
        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "visit_entry_#{visit.id}")
      end

      it 'refreshes the pending-suggestions badge so it does not go stale' do
        create_list(:visit, 2, user:, status: :suggested) # 3 suggested total

        patch visit_url(visit), params: { visit: { status: :confirmed } }, as: :turbo_stream

        expect_turbo_stream_action('replace', 'timeline-suggestions-badge')
        # One of the three was just confirmed → badge should read 2.
        expect(response.body).to match(/timeline-suggestions-badge.*\b2\b/m)
      end

      it 'sets visit name from place when place_id is provided' do
        place = create(:place, user:, name: 'Coffee Shop')
        patch visit_url(visit), params: { visit: { place_id: place.id } }, as: :turbo_stream

        expect(visit.reload.name).to eq('Coffee Shop')
        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "visit_entry_#{visit.id}")
      end

      it 'rejects place_id belonging to another user (IDOR guard)' do
        other_user = create(:user)
        other_place = create(:place, user: other_user, name: "Stranger's Place")

        original_place_id = visit.place_id
        patch visit_url(visit),
              params: { visit: { place_id: other_place.id } }, as: :turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
        expect(visit.reload.place_id).to eq(original_place_id)
      end

      context 'when user is on Lite plan with archived visit (>12 months old)' do
        let(:lite_user) do
          u = create(:user)
          u.update_columns(plan: User.plans[:lite])
          u
        end
        let!(:archived_visit) do
          create(:visit, user: lite_user, status: :suggested,
                         started_at: 13.months.ago,
                         ended_at: 13.months.ago + 1.hour)
        end

        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
          sign_out user
          sign_in lite_user
        end

        it 'returns 404 on PATCH for an archived visit outside the 12-month window' do
          patch visit_url(archived_visit), params: { visit: { status: :confirmed } }

          expect(response).to have_http_status(:not_found)
        end

        it 'returns 404 on DELETE for an archived visit outside the 12-month window' do
          delete visit_url(archived_visit)

          expect(response).to have_http_status(:not_found)
        end

        it 'still allows PATCH on a recent visit (within the window)' do
          recent_visit = create(:visit, user: lite_user, status: :suggested,
                                        started_at: 1.day.ago,
                                        ended_at: 1.day.ago + 1.hour)
          patch visit_url(recent_visit), params: { visit: { status: :confirmed } }

          expect(recent_visit.reload.status).to eq('confirmed')
        end
      end

      it 'replaces the visit_entry row on rename' do
        patch visit_url(visit), params: { visit: { name: 'New Name' } }, as: :turbo_stream

        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "visit_entry_#{visit.id}")
      end
    end

    describe 'cache busting on visit mutations' do
      let!(:visit) do
        create(:visit, user: user, status: :suggested,
                       started_at: Time.zone.parse('2026-04-15 10:00:00 UTC'),
                       ended_at: Time.zone.parse('2026-04-15 11:00:00 UTC'))
      end

      it 'deletes the MonthSummary cache for the visit month after update' do
        month_start = visit.started_at.to_date.beginning_of_month
        cache_key = Timeline::MonthSummary.cache_key_for(user, month_start)
        Rails.cache.write(cache_key, { some: 'data' })

        expect(Rails.cache.read(cache_key)).to be_present

        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'busts both old and new month caches when started_at moves across months' do
        old_month = visit.started_at.to_date.beginning_of_month
        new_started_at = '2026-05-15 10:00:00 UTC'
        new_month = Time.zone.parse(new_started_at).to_date.beginning_of_month

        old_key = Timeline::MonthSummary.cache_key_for(user, old_month)
        new_key = Timeline::MonthSummary.cache_key_for(user, new_month)
        Rails.cache.write(old_key, { some: 'old' })
        Rails.cache.write(new_key, { some: 'new' })

        patch visit_url(visit),
              params: { visit: { started_at: new_started_at, ended_at: '2026-05-15 11:00:00 UTC' } }

        expect(Rails.cache.read(old_key)).to be_nil
        expect(Rails.cache.read(new_key)).to be_nil
      end
    end
  end

  describe 'DELETE /destroy' do
    let!(:visit) { create(:visit, user:, status: :confirmed) }

    it 'removes the visit' do
      expect { delete visit_url(visit), as: :turbo_stream }.to change(Visit, :count).by(-1)
    end

    it 'returns turbo_stream removing the correct visit_entry row' do
      delete visit_url(visit), as: :turbo_stream

      expect_turbo_stream_response
      expect_turbo_stream_action('remove', "visit_entry_#{visit.id}")
    end

    it 'does NOT emit the old visit_item target' do
      delete visit_url(visit), as: :turbo_stream

      expect(response.body).not_to include("visit_item_#{visit.id}")
    end

    it 'includes the day banner stream' do
      delete visit_url(visit), as: :turbo_stream

      tz = user.safe_settings.timezone.presence || 'UTC'
      day_date = Time.use_zone(tz) { visit.started_at.in_time_zone.to_date.to_s }
      expect_turbo_stream_action('replace', "day-banner-#{day_date}")
    end

    it 'includes the filter-count streams' do
      delete visit_url(visit), as: :turbo_stream

      expect_turbo_stream_action('replace', 'filter-count-confirmed')
      expect_turbo_stream_action('replace', 'filter-count-suggested')
      expect_turbo_stream_action('replace', 'filter-count-declined')
    end

    it 'includes the calendar frame stream' do
      delete visit_url(visit), as: :turbo_stream

      expect_turbo_stream_action('replace', 'timeline-calendar-frame')
    end

    it 'includes the suggestions badge stream' do
      delete visit_url(visit), as: :turbo_stream

      expect_turbo_stream_action('replace', 'timeline-suggestions-badge')
    end

    it 'includes the success flash message' do
      delete visit_url(visit), as: :turbo_stream

      expect_flash_stream('Visit removed. Your location points are still here.')
    end

    it 'busts the MonthSummary cache for the visit month' do
      month_start = visit.started_at.to_date.beginning_of_month
      cache_key = Timeline::MonthSummary.cache_key_for(user, month_start)
      Rails.cache.write(cache_key, { some: 'data' })

      expect(Rails.cache.read(cache_key)).to be_present

      delete visit_url(visit), as: :turbo_stream

      expect(Rails.cache.read(cache_key)).to be_nil
    end

    it 'redirects to /map on HTML format' do
      delete visit_url(visit)

      expect(response).to have_http_status(:see_other)
      expect(response.location).to include('/map')
    end
  end

  describe 'POST /merge' do
    let(:tz) { 'UTC' }
    before do
      user.settings ||= {}
      user.settings['timezone'] = tz
      user.save!
    end

    let(:day) { Time.zone.parse('2025-03-15 09:00:00') }
    let!(:visit_a) do
      create(:visit, user:, started_at: day, ended_at: day + 30.minutes, duration: 30, status: :confirmed)
    end
    let!(:visit_b) do
      create(:visit, user:, started_at: day + 1.hour, ended_at: day + 90.minutes, duration: 30, status: :confirmed)
    end
    let!(:visit_c) do
      create(:visit, user:, started_at: day + 2.hours, ended_at: day + 150.minutes, duration: 30, status: :suggested)
    end

    it 'merges 2 same-day visits and returns turbo_stream' do
      post merge_visits_url(format: :turbo_stream),
           params: { visit_ids: [visit_a.id, visit_b.id] }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)

      expect { visit_a.reload }.not_to raise_error
      expect { visit_b.reload }.to raise_error(ActiveRecord::RecordNotFound)

      expect(visit_a.status).to eq('confirmed')
      expect(visit_a.started_at).to eq(day)
      expect(visit_a.ended_at).to eq(day + 90.minutes)
    end

    it 'merges 3 same-day visits across mixed statuses' do
      post merge_visits_url(format: :turbo_stream),
           params: { visit_ids: [visit_a.id, visit_b.id, visit_c.id] }

      expect(response).to have_http_status(:ok)
      expect(Visit.where(id: [visit_b.id, visit_c.id])).to be_empty
      expect(visit_a.reload.status).to eq('confirmed')
    end

    it 'rejects when fewer than 2 visit_ids are submitted' do
      post merge_visits_url(format: :turbo_stream),
           params: { visit_ids: [visit_a.id] }

      expect(response).to have_http_status(:unprocessable_content)
      expect { visit_a.reload }.not_to raise_error
    end

    it 'rejects when a visit_id belongs to another user' do
      other_user_visit = create(:visit, user: create(:user), started_at: day, ended_at: day + 5.minutes, duration: 5)

      post merge_visits_url(format: :turbo_stream),
           params: { visit_ids: [visit_a.id, other_user_visit.id] }

      expect(response).to have_http_status(:not_found)
      expect { visit_a.reload }.not_to raise_error
      expect { other_user_visit.reload }.not_to raise_error
    end

    it 'rejects when visits span multiple days in the user timezone' do
      visit_next_day = create(:visit, user:, started_at: day + 1.day, ended_at: day + 1.day + 30.minutes, duration: 30)

      post merge_visits_url(format: :turbo_stream),
           params: { visit_ids: [visit_a.id, visit_next_day.id] }

      expect(response).to have_http_status(:unprocessable_content)
      expect { visit_a.reload }.not_to raise_error
      expect { visit_next_day.reload }.not_to raise_error
    end

    it 'busts the month-summary cache for the affected month' do
      month_start = day.beginning_of_month.to_date
      cache_key = Timeline::MonthSummary.cache_key_for(user, month_start)
      Rails.cache.write(cache_key, 'sentinel')

      post merge_visits_url(format: :turbo_stream),
           params: { visit_ids: [visit_a.id, visit_b.id] }

      expect(Rails.cache.read(cache_key)).to be_nil
    end
  end

  describe 'PATCH /bulk_update with visit_ids (selection mode)' do
    let!(:visit_a) { create(:visit, user:, status: :suggested) }
    let!(:visit_b) { create(:visit, user:, status: :suggested) }
    let!(:visit_c) { create(:visit, user:, status: :suggested) }

    it 'confirms only the selected visits, not the rest' do
      patch bulk_update_visits_url, params: { status: 'confirmed', visit_ids: [visit_a.id, visit_b.id] }

      expect(visit_a.reload.status).to eq('confirmed')
      expect(visit_b.reload.status).to eq('confirmed')
      expect(visit_c.reload.status).to eq('suggested')
    end

    it 'declines only the selected visits' do
      patch bulk_update_visits_url, params: { status: 'declined', visit_ids: [visit_a.id] }

      expect(visit_a.reload.status).to eq('declined')
      expect(visit_b.reload.status).to eq('suggested')
    end

    it 'rejects the whole batch when an id belongs to another user' do
      other_user_visit = create(:visit, user: create(:user), status: :suggested)

      patch bulk_update_visits_url(format: :turbo_stream),
            params: { status: 'confirmed', visit_ids: [visit_a.id, other_user_visit.id] }

      expect(response).to have_http_status(:not_found)
      expect(visit_a.reload.status).to eq('suggested')
      expect(other_user_visit.reload.status).to eq('suggested')
    end

    it 'falls back to source_status scoping when visit_ids is absent' do
      patch bulk_update_visits_url, params: { status: 'confirmed', source_status: 'suggested' }

      expect([visit_a, visit_b, visit_c].each(&:reload).map(&:status)).to all(eq('confirmed'))
    end

    it 'rejects when more than the maximum number of visit_ids are submitted' do
      ids = (1..(VisitsController::MAX_BULK_VISIT_IDS + 1)).to_a

      patch bulk_update_visits_url(format: :turbo_stream), params: { status: 'confirmed', visit_ids: ids }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(VisitsController::MAX_BULK_VISIT_IDS.to_s)
      expect([visit_a, visit_b, visit_c].each(&:reload).map(&:status)).to all(eq('suggested'))
    end

    it 'rejects when fallback (status-only) scoping would exceed the maximum' do
      stub_const('VisitsController::MAX_BULK_VISIT_IDS', 2)

      patch bulk_update_visits_url(format: :turbo_stream),
            params: { status: 'confirmed', source_status: 'suggested' }

      expect(response).to have_http_status(:unprocessable_content)
      expect([visit_a, visit_b, visit_c].each(&:reload).map(&:status)).to all(eq('suggested'))
    end
  end

  describe 'DELETE /bulk_destroy' do
    let!(:visit_a) { create(:visit, user:, status: :suggested) }
    let!(:visit_b) { create(:visit, user:, status: :confirmed) }
    let!(:visit_c) { create(:visit, user:, status: :suggested) }

    it 'destroys the selected visits' do
      delete bulk_destroy_visits_url(format: :turbo_stream),
             params: { visit_ids: [visit_a.id, visit_b.id] }

      expect(response).to have_http_status(:ok)
      expect(Visit.where(id: [visit_a.id, visit_b.id])).to be_empty
      expect(Visit.where(id: visit_c.id)).to exist
    end

    it 'rejects when no visit_ids are submitted' do
      delete bulk_destroy_visits_url(format: :turbo_stream), params: { visit_ids: [] }

      expect(response).to have_http_status(:unprocessable_content)
      expect { visit_a.reload }.not_to raise_error
    end

    it 'rejects when an id belongs to another user' do
      other_user_visit = create(:visit, user: create(:user))

      delete bulk_destroy_visits_url(format: :turbo_stream),
             params: { visit_ids: [visit_a.id, other_user_visit.id] }

      expect(response).to have_http_status(:not_found)
      expect { visit_a.reload }.not_to raise_error
      expect { other_user_visit.reload }.not_to raise_error
    end

    it 'busts the month-summary cache for affected months' do
      month_start = visit_a.started_at.beginning_of_month.to_date
      cache_key = Timeline::MonthSummary.cache_key_for(user, month_start)
      # Pre-populate with a valid MonthSummary shape so the calendar stream can
      # render during the action, then verify the after_action busts the key.
      sentinel = { month: month_start.strftime('%Y-%m'), weeks: [], days: {}, status_counts: {} }
      Rails.cache.write(cache_key, sentinel)

      expect(Rails.cache.read(cache_key)).to be_present

      delete bulk_destroy_visits_url(format: :turbo_stream),
             params: { visit_ids: [visit_a.id] }

      expect(Rails.cache.read(cache_key)).to be_nil
    end

    it 'nullifies points\' visit_id rather than deleting them' do
      point = create(:point, user: user, visit: visit_a)

      delete bulk_destroy_visits_url(format: :turbo_stream),
             params: { visit_ids: [visit_a.id] }

      expect(Point.where(id: point.id)).to exist
      expect(point.reload.visit_id).to be_nil
    end

    it 'rejects when more than the maximum number of visit_ids are submitted' do
      ids = (1..(VisitsController::MAX_BULK_VISIT_IDS + 1)).to_a

      delete bulk_destroy_visits_url(format: :turbo_stream), params: { visit_ids: ids }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(VisitsController::MAX_BULK_VISIT_IDS.to_s)
    end

    it 'returns the Lite-window upgrade hint when an archived visit id is submitted' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :lite)
      old_visit = create(:visit, user: user,
                                  started_at: 13.months.ago,
                                  ended_at: 13.months.ago + 30.minutes)

      delete bulk_destroy_visits_url(format: :turbo_stream),
             params: { visit_ids: [visit_a.id, old_visit.id] }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('Lite plan')
      expect { old_visit.reload }.not_to raise_error
      expect { visit_a.reload }.not_to raise_error
    end

    it 'busts caches for every month touched when the deletion spans months' do
      tz = user.safe_settings.timezone.presence || 'UTC'
      apr_start = Time.use_zone(tz) { Time.zone.local(2026, 4, 30, 10, 0) }
      may_start = Time.use_zone(tz) { Time.zone.local(2026, 5, 1, 10, 0) }
      apr_visit = create(:visit, user:, started_at: apr_start, ended_at: apr_start + 30.minutes)
      may_visit = create(:visit, user:, started_at: may_start, ended_at: may_start + 30.minutes)
      apr_key = Timeline::MonthSummary.cache_key_for(user, apr_start.to_date.beginning_of_month)
      may_key = Timeline::MonthSummary.cache_key_for(user, may_start.to_date.beginning_of_month)
      Rails.cache.write(apr_key, 'sentinel-apr')
      Rails.cache.write(may_key, 'sentinel-may')

      delete bulk_destroy_visits_url(format: :turbo_stream),
             params: { visit_ids: [apr_visit.id, may_visit.id] }

      expect(Rails.cache.read(apr_key)).to be_nil
      expect(Rails.cache.read(may_key)).to be_nil
    end

    it 'includes the calendar frame stream in the turbo response' do
      delete bulk_destroy_visits_url(format: :turbo_stream),
             params: { visit_ids: [visit_a.id] }

      expect_turbo_stream_response
      expect_turbo_stream_action('replace', 'timeline-calendar-frame')
    end

    context 'with date + source_status instead of visit_ids (Delete all path)' do
      let(:tz) { 'UTC' }

      before do
        user.settings ||= {}
        user.settings['timezone'] = tz
        user.save!
        Visit.delete_all
      end

      let!(:suggested_today) do
        create(:visit, user:, status: :suggested,
                       started_at: Time.zone.today.beginning_of_day + 9.hours,
                       ended_at: Time.zone.today.beginning_of_day + 10.hours)
      end
      let!(:suggested_today_2) do
        create(:visit, user:, status: :suggested,
                       started_at: Time.zone.today.beginning_of_day + 11.hours,
                       ended_at: Time.zone.today.beginning_of_day + 12.hours)
      end
      let!(:confirmed_today) do
        create(:visit, user:, status: :confirmed,
                       started_at: Time.zone.today.beginning_of_day + 13.hours,
                       ended_at: Time.zone.today.beginning_of_day + 14.hours)
      end

      it 'deletes all visits with the given status on the given date' do
        delete bulk_destroy_visits_url(format: :turbo_stream),
               params: { date: Time.zone.today.to_s, source_status: 'suggested' }

        expect(response).to have_http_status(:ok)
        expect(Visit.where(id: [suggested_today.id, suggested_today_2.id])).to be_empty
        expect(Visit.where(id: confirmed_today.id)).to exist
      end

      it 'returns the turbo stream response with calendar frame' do
        delete bulk_destroy_visits_url(format: :turbo_stream),
               params: { date: Time.zone.today.to_s, source_status: 'suggested' }

        expect_turbo_stream_response
        expect_turbo_stream_action('replace', 'timeline-calendar-frame')
      end

      it 'does not touch visits of other users' do
        other_visit = create(:visit, user: create(:user), status: :suggested,
                                     started_at: Time.zone.today.beginning_of_day + 9.hours,
                                     ended_at: Time.zone.today.beginning_of_day + 10.hours)

        delete bulk_destroy_visits_url(format: :turbo_stream),
               params: { date: Time.zone.today.to_s, source_status: 'suggested' }

        expect { other_visit.reload }.not_to raise_error
      end

      it 'returns unprocessable when no visits match date + source_status' do
        delete bulk_destroy_visits_url(format: :turbo_stream),
               params: { date: '1900-01-01', source_status: 'suggested' }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns unprocessable when neither visit_ids nor date+source_status are given' do
        delete bulk_destroy_visits_url(format: :turbo_stream), params: {}

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
