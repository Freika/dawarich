# frozen_string_literal: true

module ShareManagementFixtureSupport
  def management_id(number) = format('a9f10000-0000-4000-8000-%012d', number)

  def management_actor(id, locale: 'en')
    user = create(:user, id:, email: "a9fpl-share-#{id}@dawarich.test", skip_auto_trial: true,
                         changelog_consent: :declined)
    user.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'locale' => locale,
                                    'onboarding_completed' => true }, api_key: "a9fpl-fixture-#{id}",
                        plan: User.plans[:pro], status: User.statuses[:active], active_until: now + 30.days)
    user.reload
  end

  def management_link(user, number, type: 'live', resource_id: nil, **extra)
    SharedLink.create!({ id: management_id(number), user:, resource_type: type, resource_id:,
                         name: "Leipzig #{type} #{number}", settings: SharedLink.default_settings_for(type),
                         created_at: now - number.hours, updated_at: now }.merge(extra))
  end

  def management_trip(user, id)
    Trip.insert!({ id:, user_id: user.id, name: 'Leipzig Weekend', started_at: now - 3.days,
                   ended_at: now - 1.day, distance: 1500, created_at: now, updated_at: now,
                   path: 'LINESTRING(12.3731 51.3397,12.3811 51.3437)' })
  end

  def management_seed(user, foreign)
    SharedLink.where(user_id: [user.id, foreign.id]).delete_all
    management_link(user, 1, magic_phrase: 'old-fixture-phrase', created_at: now - 2.hours)
    management_link(user, 2, created_at: now - 1.hour)
    management_link(user, 3).update_columns(expires_at: now - 1.second)
    management_link(user, 4, revoked_at: now)
    management_link(user, 5, type: 'timeline', settings: { 'start_date' => '2026-09-01',
                                                        'end_date' => '2026-09-07' })
    management_link(user, 6, type: 'trip', resource_id: 99_101)
    management_link(user, 7, type: 'track', resource_id: 99_103)
    management_link(foreign, 8)
  end

  def management_rows(table)
    predicate = table == 'shared_links' ? 'user_id IN (98101, 98102)' : 'id IN (99101, 99102)'
    sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{predicate} ORDER BY id"
    ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }
  end

  def management_actors
    User.where(id: [98_101, 98_102]).order(:id).map do |user|
      { 'id' => user.id, 'email' => user.email, 'settings' => user.settings, 'theme' => user.theme,
        'plan' => User.plans[user.plan], 'status' => User.statuses[user.status],
        'active_until' => user.active_until.iso8601(6),
        'changelog_consent' => User.changelog_consents[user.changelog_consent] }
    end
  end

  def management_document
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
    doc.css('meta[name="csrf-token"]').each { |meta| meta['content'] = 'CSRF' }
    doc.css('#session_dump pre').each { |dump| dump.content = 'SESSION' }
    doc.css('#env_dump pre').each do |dump|
      dump.content = dump.content.gsub(/(HTTP_X_CSRF_TOKEN: )"[^"]*"/, '\1"CSRF"')
    end
    node = doc.at_css('body > div.container > div.w-full > div.flex') || doc.at_css('body')
    html = node ? node.inner_html : response.body
    streams = doc.css('turbo-stream').map { |s| { 'action' => s['action'], 'target' => s['target'] } }
    if response.media_type == 'text/vnd.turbo-stream.html'
      expect(streams).to eq([{ 'action' => 'update', 'target' => 'share-hub-body' },
                             { 'action' => 'replace', 'target' => 'live-share-indicator' }])
    end
    [html, streams]
  end

  def capture_management(name, user, verb, path, params: {}, headers: {}, json: false)
    Rails.cache.clear
    reset!
    sign_in user.reload if user
    if verb != :get
      get '/share_links/live/new'
      csrf = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      headers = headers.merge('X-CSRF-Token' => csrf)
    end
    before = management_rows('shared_links')
    events = []
    observer = ActiveSupport::Notifications.subscribe('broadcast.action_cable') do |_name, _start, _end, _id, payload|
      events << { 'stream' => payload[:broadcasting], 'message' => payload[:message].deep_stringify_keys }
    end
    send(verb, path, params:, headers:, **(json ? { as: :json } : {}))
    html, streams = management_document
    data = { 'path' => path, 'verb' => verb.to_s.upcase, 'params' => params.deep_stringify_keys,
             'headers' => headers.except('X-CSRF-Token'), 'json_request' => json,
             'now' => now.iso8601, 'actor_id' => user&.id,
             'status' => response.status, 'location' => response.headers['Location'],
             'content_type' => response.media_type, 'flash' => flash.to_hash, 'streams' => streams,
             'actors' => management_actors, 'trips' => management_rows('trips'),
             'before' => before, 'after' => management_rows('shared_links'), 'events' => events }
    File.write(dir.join("#{name}.html"), html)
    File.write(dir.join("#{name}.json"), "#{Oj.dump(data, mode: :strict, float_precision: 0, indent: 2)}\n")
    sign_out user if user
    data
  ensure
    ActiveSupport::Notifications.unsubscribe(observer) if observer
  end
end
