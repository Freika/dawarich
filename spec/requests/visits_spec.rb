# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/visits', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET /index (retired)' do
    it 'VisitsController no longer responds to #index' do
      expect(VisitsController.action_methods).not_to include('index')
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

      it 'sets visit name from place when place_id is provided' do
        place = create(:place, user:, name: 'Coffee Shop')
        patch visit_url(visit), params: { visit: { place_id: place.id } }, as: :turbo_stream

        expect(visit.reload.name).to eq('Coffee Shop')
        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "visit_entry_#{visit.id}")
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
    end
  end

  describe 'DELETE /destroy' do
    let!(:visit) { create(:visit, user:, status: :confirmed) }

    it 'removes the visit' do
      expect { delete visit_url(visit), as: :turbo_stream }.to change(Visit, :count).by(-1)
    end

    it 'returns turbo_stream removing the visit row' do
      delete visit_url(visit), as: :turbo_stream

      expect_turbo_stream_response
      expect_turbo_stream_action('remove', "visit_item_#{visit.id}")
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
end
