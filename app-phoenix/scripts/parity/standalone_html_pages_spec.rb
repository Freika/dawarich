# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Standalone HTML GET route characterization', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:destination) { Rails.root.join('app-phoenix/test/fixtures/standalone/html_pages.json') }

  def seed_pages
    user = create(:user, id: 94_801, email: 'html-pages@example.invalid', admin: true,
                         password: 'synthetic-html-pages-password', changelog_consent: :declined)
    user.update_columns(settings: { 'timezone' => 'UTC', 'onboarding_completed' => true },
                        theme: 'dark', api_key: 'synthetic-html-pages-key', active_until: Time.utc(3026),
                        last_sign_in_at: Time.utc(2026, 3, 1))
    import = create(:import, id: 94_801, user:)
    create(:point, id: 94_801, user:, import:, timestamp: Time.utc(2026, 3, 1, 10).to_i)
    trip = create(:trip, id: 94_801, user:, name: 'Synthetic trip', description: '',
                         started_at: Time.utc(2026, 3, 1), ended_at: Time.utc(2026, 3, 2))
    create(:track, id: 94_801, user:, start_at: trip.started_at, end_at: trip.ended_at)
    create(:place, id: 94_801, user:, name: 'Synthetic place')
    create(:tag, id: 94_801, user:, name: 'Synthetic tag')
    create(:notification, id: 94_801, user:, title: 'Synthetic notification')
    stat = create(:stat, :with_sharing_enabled, id: 94_801, user:, year: 2026, month: 3)
    digest = create(:users_digest, :with_sharing_enabled, id: 94_801, user:, year: 2026)
    create(:shared_link, id: 'a9480100-0000-4000-8000-000000000002', user:, resource_type: :track, resource_id: 94_801)
    share = create(:shared_link, id: 'a9480100-0000-4000-8000-000000000001', user:, trip:)
    family = create(:family, id: 94_801, creator: user)
    create(:family_membership, id: 94_801, family:, user:, role: :owner)
    invitation = create(:family_invitation, id: 94_801, family:, invited_by: user,
                                            email: 'synthetic-invite@example.invalid',
                                            token: 'synthetic-html-pages-invitation')
    other = create(:user, id: 94_802, email: 'html-other@example.invalid')
    other.update_columns(api_key: 'synthetic-html-other-key')
    create(:family_membership, id: 94_802, family:, user: other, role: :member)
    create(:family_location_request, id: 94_801, family:, requester: other, target_user: user)
    progress = create(:achievement_progress, id: 94_801, user:, achievement_key: 'continent_europe',
                                            sharing_enabled: true, sharing_uuid: SecureRandom.uuid)
    TripSource.insert!({ id: 94_801, user_id: user.id, provider: 'trek', base_url: 'https://trek.example.invalid',
                         api_key: nil, status: 1, created_at: Time.current, updated_at: Time.current })
    [user.reload, { '/s/:id' => share.id, '/invitations/:token' => invitation.token,
                    '/family/invitations/:id' => invitation.token,
                    '/shared/month/:uuid' => stat.sharing_uuid, '/shared/digest/:uuid' => digest.sharing_uuid,
                    '/shared/achievements/:uuid' => progress.sharing_uuid,
                    '/shared/achievements/:uuid/og.png' => progress.sharing_uuid }]
  end

  def concrete_path(pattern, substitutions)
    return pattern.sub(/:(?:id|token|uuid)/, substitutions[pattern]) if substitutions.key?(pattern)

    pattern.gsub(/:(?:track_id|trip_id|id)/, '94801').gsub(':year', '2026').gsub(':month', '3')
           .gsub(':key', 'continent_europe').gsub(':uuid', 'synthetic-missing').gsub(':token', 'synthetic-missing')
  end

  def typical_params(pattern)
    case pattern
    when '/points'
      { start_at: '2025-09-07T00:00', end_at: '2026-10-07T23:59', import_id: '', commit: 'Search' }
    when '/imports' then { sort_by: 'created_at', sort_order: 'desc', page: '1' }
    when '/trips', '/places', '/exports', '/notifications', '/tags' then { page: '1' }
    when '/insights' then { year: '2026' }
    when '/insights/details' then { year: '2026', month: '3' }
    when '/admin/settings' then { section: 'photon' }
    when '/settings/integrations' then { service: 'trek' }
    when '/settings/theme' then { theme: 'dark' }
    when '/settings/users' then { search: '', page: '1' }
    when '/places/nearby' then { latitude: '51.3', longitude: '12.3', radius: '100', limit: '10' }
    when '/achievements/:key' then { q: '', status: 'all', page: '1' }
    when '/map/timeline_feeds', '/map/timeline_feeds/calendar'
      { date: '2026-03-01', status: 'confirmed' }
    when '/map/residency' then { year: '2026' }
    when '/map', '/map/v2' then { start_at: '2026-03-01T00:00', end_at: '2026-03-02T23:59' }
    else {}
    end
  end

  def capture(user, route, substitutions)
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      result = capture_request(user, route, substitutions)
      raise ActiveRecord::Rollback
    end
    result
  end

  def capture_request(user, route, substitutions)
    pattern = route.path.spec.to_s.delete_suffix('(.:format)')
    path = concrete_path(pattern, substitutions)
    params = typical_params(pattern)
    target = params.empty? ? path : "#{path}?#{params.to_query}"
    reset!
    sign_in(user)
    get(target, headers: { 'Accept' => 'text/html' })
    entry = { pattern:, target:, controller: route.defaults[:controller], action: route.defaults[:action],
              rails_status: response.status, html: response.media_type == 'text/html' }
    return entry unless entry[:html] && entry[:rails_status] == 200

    forms = Nokogiri::HTML5(response.body).css('form[method="get"]').map do |form|
      values = form.css('input[name], select[name]').to_h do |input|
        value = if input.name == 'select'
                  input.at_css('option[selected]')&.[]('value') || input.at_css('option')&.[]('value') || ''
                else
                  input['value'] || ''
                end
        [input['name'], value]
      end
      { action: form['action'], params: values }
    end
    entry.merge(forms:)
  rescue StandardError => e
    { pattern:, target:, controller: route.defaults[:controller], action: route.defaults[:action],
      rails_error: e.class.name, constraint: e.message[/null value in column "[^"]+" of relation "[^"]+"/] }
  end

  def rows
    tables = %w[imports points tracks trips places tags notifications stats digests shared_links families
                family_memberships family_invitations family_location_requests achievement_progresses trip_sources]
    tables.to_h do |table|
      data = ActiveRecord::Base.connection.select_all("SELECT * FROM #{table}").to_a
      json_columns = ActiveRecord::Base.connection.columns(table).select do |column|
        %i[json jsonb].include?(column.type)
      end.map(&:name)
      data.each do |row|
        %w[lonlat original_path path matched_path].each do |key|
          next unless row[key]

          sql = "SELECT ST_AsEWKT(#{key}::geometry) FROM #{table} WHERE id=#{row['id']}"
          row[key] = ActiveRecord::Base.connection.select_value(sql)
        end
        row.delete('api_key') if table == 'trip_sources'
        row.each do |key, value|
          row[key] = value.utc.iso8601(6) if value.respond_to?(:utc)
          row[key] = JSON.parse(value) if value.is_a?(String) && json_columns.include?(key)
        end
      end
      [table, data]
    end
  end

  it 'records every application HTML GET declaration and Rails form envelope' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    travel_to(Time.utc(2026, 10, 7, 12)) do
      user, substitutions = seed_pages
      routes = Rails.application.routes.routes.select do |route|
        route.verb.include?('GET') && !route.path.spec.to_s.start_with?('/api/') &&
          !route.path.spec.to_s.start_with?('/rails/') &&
          !route.defaults[:controller].to_s.start_with?('api/', 'rails/', 'active_storage/', 'rails_icons/', 'turbo/')
      end
      users = User.order(:id).map do |actor|
        fields = %w[id email admin theme settings active_until created_at updated_at last_sign_in_at api_key]
        actor.attributes.slice(*fields).merge(
          'active_until' => actor.active_until.utc.iso8601(6),
          'created_at' => actor.created_at.utc.iso8601(6), 'updated_at' => actor.updated_at.utc.iso8601(6),
          'last_sign_in_at' => actor.last_sign_in_at&.utc&.iso8601(6),
          'changelog_consent' => User.changelog_consents[actor.changelog_consent],
          'plan' => User.plans[actor.plan], 'status' => User.statuses[actor.status]
        )
      end
      captures = routes.map { |route| capture(user, route, substitutions) }
      forms = captures.flat_map do |entry|
        (entry[:forms] || []).map do |form|
          uri = URI.parse(form[:action])
          params = Rack::Utils.parse_query(uri.query).merge(form[:params])
          target = "#{uri.path}?#{params.to_query}"
          reset!
          sign_in(user)
          get(target, headers: { 'Accept' => 'text/html' })
          { pattern: entry[:pattern], target:, rails_status: response.status,
            html: response.media_type == 'text/html', form_submission: true }
        end
      end
      extras = ['/api-docs', '/api-docs/index.html', '/sidekiq', '/admin/flipper',
                '/s/a9480100-0000-4000-8000-000000000002'].map do |target|
        reset!
        sign_in(user)
        get(target, headers: { 'Accept' => 'text/html' })
        expected = { '/sidekiq' => 302, '/admin/flipper' => 404 }[target]
        { pattern: target, target:, rails_status: response.status, html: response.media_type == 'text/html',
native_status: expected }
      end
      fixture = { user_id: user.id, users:, rows:, routes: captures + forms + extras }
      File.write(destination, "#{JSON.pretty_generate(fixture)}\n")
      expect(fixture[:routes].find { |route| route[:pattern] == '/points' }[:rails_status]).to eq(200)
      expect(fixture[:routes].size).to be > 70
    end
  end
end
