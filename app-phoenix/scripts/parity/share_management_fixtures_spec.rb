# frozen_string_literal: true

require 'rails_helper'
require_relative 'share_management_fixture_support'

RSpec.describe 'Phoenix fixtures: authenticated share management', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ShareManagementFixtureSupport

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/share_management') }
  let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }

  before do
    FileUtils.mkdir_p(dir)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(SharedLink::PhraseGenerator).to receive(:call).and_return('blue-fixture-hill')
  end

  around do |example|
    number = 1000
    assign_id = lambda do |record|
      number += 1
      record.id ||= format('a9f10000-0000-4000-8000-%012d', number)
    end
    SharedLink.set_callback(:create, :before, assign_id)
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    SharedLink.skip_callback(:create, :before, assign_id)
    ActionController::Base.allow_forgery_protection = false
  end

  def management_pages(user, foreign, locale)
    SharedLink.where(user_id: [user.id, foreign.id]).delete_all
    capture_management("hub_guest_#{locale}", nil, :get, "/share_links/hub?locale=#{locale}")
    %w[live shared unknown timeline make].each do |tab|
      capture_management("hub_empty_#{tab}_#{locale}", user, :get, "/share_links/hub?tab=#{tab}")
    end
    capture_management("hub_range_#{locale}", user, :get,
                       '/share_links/hub?tab=timeline&start_date=2026-09-03&end_date=2026-09-10')
    capture_management("hub_bad_range_#{locale}", user, :get,
                       '/share_links/hub?tab=timeline&start_date=malformed&end_date=')
    %w[document frame].each do |shape|
      headers = shape == 'frame' ? { 'Turbo-Frame' => 'share-link-modal' } : {}
      capture_management("live_new_#{shape}_#{locale}", user, :get, '/share_links/live/new', headers:)
      capture_management("trip_new_#{shape}_#{locale}", user, :get, '/trips/99101/share_link/new', headers:)
    end
    capture_management("trip_missing_#{locale}", user, :get, '/trips/99999/share_link/new')
    capture_management("trip_foreign_#{locale}", user, :get, '/trips/99102/share_link/new')
    management_seed(user, foreign)
    %w[live timeline shared unknown].each do |tab|
      capture_management("hub_active_#{tab}_#{locale}", user, :get, "/share_links/hub?tab=#{tab}")
    end
    capture_management("live_active_#{locale}", user, :get, '/share_links/live/new')
    capture_management("trip_active_#{locale}", user, :get, '/trips/99101/share_link/new')
    capture_management("live_active_frame_#{locale}", user, :get, '/share_links/live/new',
                       headers: { 'Turbo-Frame' => 'share-link-modal' })
    capture_management("trip_active_frame_#{locale}", user, :get, '/trips/99101/share_link/new',
                       headers: { 'Turbo-Frame' => 'share-link-modal' })
  end

  def management_creates(user, foreign, locale)
    values = { 'blank' => '', 'malformed' => 'wrong', 'past' => '2026-09-01',
               'future' => '2026-10-25', 'dst_after' => '2026-10-26' }
    { 'live' => '/share_links/live', 'trip' => '/trips/99101/share_link' }.each do |type, path|
      values.each do |label, expiry|
        management_seed(user, foreign)
        capture_management("#{type}_expiry_#{label}_#{locale}", user, :post, path,
                           params: { shared_link: { name: '', magic_phrase: '', expires_at: expiry } })
      end
      %w[name magic_phrase].each do |key|
        management_seed(user, foreign)
        capture_management("#{type}_invalid_#{key}_#{locale}", user, :post, path,
                           params: { shared_link: { key => 'a' * 256 } })
      end
      management_seed(user, foreign)
      capture_management("#{type}_settings_#{locale}", user, :post, path,
                         params: { shared_link: { settings: { show_photos: '0', show_stats: 'false',
                                                              show_route: '1', show_countries: '',
                                                              show_description: 'off', show_days: 'yes',
                                                              show_day_notes: nil, ignored: '1' } } })
    end
    %w[blank false true].each do |hub|
      management_seed(user, foreign)
      capture_management("live_hub_#{hub}_#{locale}", user, :post, '/share_links/live',
                         params: { hub: hub == 'blank' ? '' : hub, shared_link: {} })
    end
    management_seed(user, foreign)
    capture_management("live_invalid_hub_#{locale}", user, :post, '/share_links/live',
                       params: { hub: 'false', shared_link: { magic_phrase: 'a' * 256 } })
    management_seed(user, foreign)
    capture_management("live_invalid_frame_#{locale}", user, :post, '/share_links/live',
                       headers: { 'Turbo-Frame' => 'share-link-modal' },
                       params: { shared_link: { expires_at: '2020-01-01' } })
    management_seed(user, foreign)
    capture_management("live_json_create_#{locale}", user, :post, '/share_links/live',
                       json: true, params: { shared_link: {} })
    management_seed(user, foreign)
    capture_management("live_turbo_create_#{locale}", user, :post, '/share_links/live',
                       headers: { 'Accept' => 'text/vnd.turbo-stream.html' }, params: { shared_link: {} })
    %w[UTC America/Havana Asia/Tokyo Europe/Berlin].each do |zone|
      user.update_columns(settings: user.settings.merge('timezone' => zone))
      management_seed(user, foreign)
      capture_management("live_expiry_#{zone.tr('/', '_')}_#{locale}", user, :post, '/share_links/live',
                         params: { shared_link: { expires_at: '2026-11-01' } })
    end
  end

  def management_mutations(user, foreign, locale)
    { 'live' => '/share_links/live', 'trip' => '/trips/99101/share_link' }.each do |type, path|
      { 'delete' => [:delete, ''], 'revoke' => [:patch, '/revoke'],
        'url' => [:post, '/regenerate'], 'phrase' => [:post, '/regenerate_phrase'] }.each do |action, (verb, suffix)|
        management_seed(user, foreign)
        capture_management("#{type}_#{action}_#{locale}", user, verb, path + suffix)
        SharedLink.where(user_id: user.id).delete_all
        capture_management("#{type}_#{action}_missing_#{locale}", user, verb, path + suffix)
      end
    end
    { 'live' => 1, 'trip' => 6, 'timeline' => 5, 'track' => 7, 'foreign' => 8, 'missing' => 99 }.each do |type, id|
      management_seed(user, foreign)
      capture_management("shared_revoke_#{type}_#{locale}", user, :patch,
                         "/share_links/shares/#{management_id(id)}/revoke", params: { hub: '1' })
    end
    management_seed(user, foreign)
    capture_management("ambiguous_override_#{locale}", user, :post, '/share_links/live',
                       params: { _method: 'patch' }, headers: { 'X-HTTP-Method-Override' => 'DELETE' })
  end

  it 'writes live trip hub and mutation contracts with stable IDs' do
    travel_to now do
      user = management_actor(98_101)
      foreign = management_actor(98_102)
      management_trip(user, 99_101)
      management_trip(foreign, 99_102)
      %w[en de es fr pl ca zh].each do |locale|
        user.update_columns(settings: user.settings.merge('locale' => locale))
        management_pages(user, foreign, locale)
        management_creates(user, foreign, locale)
        management_mutations(user, foreign, locale)
      end
      expect(File.exist?(dir.join('hub_empty_live_en.json'))).to be(true)
      %w[en de es fr pl ca zh].each do |locale|
        html = File.read(dir.join("ambiguous_override_#{locale}.html"))
        expect(html).not_to match(/_csrf_token:|session_id:|warden\.user\.user\.key:/)
        expect(html).to include('HTTP_X_CSRF_TOKEN: "CSRF"')
      end
    end
  end

  it 'writes track and timeline six-action contracts and failed replacement rollback' do
    target = dir.join('a12f3b')
    allow(self).to receive(:dir).and_return(target)
    travel_to now do
      user = management_actor(98_101)
      foreign = management_actor(98_102)
      management_trip(user, 99_101)
      management_trip(foreign, 99_102)
      [user, foreign].each_with_index do |actor, index|
        Track.insert!({ id: 99_103 + index, user_id: actor.id, start_at: now - 2.hours,
                        end_at: now - 1.hour, distance: 1500, dominant_mode: 1,
                        original_path: 'LINESTRING(12.3731 51.3397,12.3811 51.3437)',
                        created_at: now, updated_at: now })
      end
      { 'track' => '/tracks/99103/share_link', 'timeline' => '/share_links/timeline' }.each do |type, base|
        management_seed(user, foreign)
        capture_management("#{type}_new_en", user, :get, "#{base}/new",
                           headers: { 'Turbo-Frame' => 'share-link-modal' })
        head = capture_management("#{type}_head_en", user, :head, "#{base}/new")
        expect(head['status']).to eq(200)
        SharedLink.where(user_id: user.id, resource_type: type).delete_all
        capture_management("#{type}_empty_new_en", user, :get, "#{base}/new",
                           headers: { 'Turbo-Frame' => 'share-link-modal' })
        attrs = { name: '', magic_phrase: 'synthetic-phrase', expires_at: '2026-10-25',
                  settings: { show_photos: '1' } }
        attrs.merge!(start_date: '2026-09-01', end_date: '2026-09-07') if type == 'timeline'
        created = capture_management("#{type}_create_en", user, :post, base, params: { shared_link: attrs })
        expect(created['status']).to eq(302)
        before = management_rows('shared_links')
        failed = capture_management("#{type}_invalid_en", user, :post, base,
                                    params: { shared_link: attrs.merge(magic_phrase: 'x' * 256) })
        expect(failed['status']).to eq(422)
        expect(management_rows('shared_links')).to eq(before)
        { 'url' => [:post, '/regenerate'], 'phrase' => [:post, '/regenerate_phrase'],
          'revoke' => [:patch, '/revoke'] }.each do |label, (verb, suffix)|
          result = capture_management("#{type}_#{label}_en", user, verb, base + suffix)
          expect(result['status']).to eq(302)
        end
        capture_management("#{type}_recreate_en", user, :post, base, params: { shared_link: attrs })
        deleted = capture_management("#{type}_delete_en", user, :delete, base)
        expect(deleted['status']).to eq(302)
      end
      foreign_track = capture_management('track_foreign_en', user, :get, '/tracks/99104/share_link/new')
      expect(foreign_track['status']).to eq(404)
    end
  end

  it 'failed live replacement rolls back rows but broadcasts revoked to old links' do
    travel_to now do
      user = management_actor(98_101)
      link = management_link(user, 1)
      data = nil
      expect do
        data = capture_management('failed_live_replacement', user, :post, '/share_links/live',
                                  params: { shared_link: { magic_phrase: 'a' * 256 } })
      end.to have_broadcasted_to(link).from_channel(SharedLocationChannel).with(revoked: true)
      expect(link.reload.revoked_at).to be_nil
      expect(data['after']).to eq(data['before'])
      expect(response.status).to eq(422)
      expect(File.exist?(dir.join('failed_live_replacement.json'))).to be(true)
    end
  end
end
