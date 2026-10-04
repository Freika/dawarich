# frozen_string_literal: true

module FamilyPagesFixtureSupport
  def family_actor(id, email, locale: 'en', plan: :family)
    user = create(:user, id:, email:, plan:, skip_auto_trial: true, changelog_consent: :declined)
    user.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'locale' => locale,
                                    'onboarding_completed' => true, 'maps' => { 'distance_unit' => 'km' } },
                        status: User.statuses[:active], active_until: now + 30.days,
                        api_key: "a9fpl-fixture-#{id}")
    user.reload
  end

  def family_graph(locale)
    owner = family_actor(90_101, 'z-owner@a9fpl.dawarich.test', locale:)
    member = family_actor(90_102, 'a-member@a9fpl.dawarich.test', locale:, plan: :lite)
    outsider = family_actor(90_103, 'invitee@a9fpl.dawarich.test', locale:, plan: :lite)
    family = Family.create!(id: 91_001, name: 'Leipzig Fixture Family', creator: owner,
                            created_at: now - 30.days, updated_at: now - 2.days)
    Family::Membership.create!(id: 92_001, family:, user: owner, role: :owner)
    Family::Membership.create!(id: 92_002, family:, user: member, role: :member)
    [owner, member, outsider, family]
  end

  def family_invitations!(family, owner, email)
    [%w[pending pending], %w[equal pending], %w[past pending], %w[accepted accepted],
     %w[cancelled cancelled], %w[expired expired]].each_with_index do |(token, status), index|
      expires_at = { 'equal' => now, 'past' => now - 1.second, 'expired' => now - 1.day }
                   .fetch(token, now + 1.day)
      Family::Invitation.create!(id: 93_001 + index, family:, invited_by: owner, email:,
                                 token: "a9fpl-#{token}", status:, expires_at:,
                                 created_at: now - (index + 1).hours, updated_at: now)
    end
  end

  def family_request!(id, family, requester, target, expires_at: now + 1.hour)
    Family::LocationRequest.create!(id:, family:, requester:, target_user: target, expires_at:,
                                    created_at: now - 1.hour, updated_at: now)
  end

  def family_points!(owner, member)
    [owner, member].each_with_index do |user, index|
      user.update_family_location_sharing!(true, duration: 'permanent')
      Point.insert_all!([
                          { id: 95_001 + index * 10, user_id: user.id, timestamp: now.to_i - 300,
                            lonlat: 'POINT(12.3731 51.3397)', anomaly: false, created_at: now, updated_at: now },
                          { id: 95_002 + index * 10, user_id: user.id, timestamp: now.to_i - 100,
                            lonlat: 'POINT(12.3811 51.3437)', anomaly: true, created_at: now, updated_at: now },
                          { id: 95_003 + index * 10, user_id: user.id, timestamp: nil,
                            lonlat: 'POINT(12.3901 51.3402)', anomaly: false, created_at: now, updated_at: now },
                          { id: 95_004 + index * 10, user_id: user.id, timestamp: now.to_i,
                            lonlat: nil, anomaly: false, created_at: now, updated_at: now }
                        ])
    end
  end

  def family_rows
    %w[families family_memberships family_invitations family_location_requests points].to_h do |table|
      predicate = case table
                  when 'families' then 'id = 91001'
                  when 'points' then 'user_id IN (90101, 90102)'
                  else 'family_id = 91001'
                  end
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{predicate} ORDER BY id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }]
    end
  end

  def family_actors
    User.where(id: [90_101, 90_102, 90_103]).order(:id).map do |user|
      user.attributes.slice('id', 'email', 'theme', 'settings', 'admin')
          .merge('subscription_source' => User.subscription_sources[user.subscription_source],
                 'changelog_consent' => User.changelog_consents[user.changelog_consent],
                 'plan' => User.plans[user.plan],
                 'status' => User.statuses[user.status],
                 'active_until' => user.active_until&.utc&.iso8601(6))
    end
  end

  def family_document(doc)
    doc.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
    doc.css('meta[name="csrf-token"]').each { |meta| meta['content'] = 'CSRF' }
    doc.css('[signed-stream-name]').each { |node| node['signed-stream-name'] = 'SIGNED' }
    doc.css('a[href*="/auth/dawarich?"]').each do |link|
      link['href'] = link['href'].sub(/([?&]token=)[^&]+/, '\1REDACTED')
    end
    node = doc.at_css('body > div.container > div.w-full > div.flex')
    node ? node.inner_html : ''
  end

  def family_controls(doc)
    doc.css('form').map do |form|
      { 'action' => form['action'], 'method' => form['method'],
        'override' => form.at_css('input[name="_method"]')&.[]('value'),
        'inputs' => form.css('[name]').map { |input| input['name'] } }
    end
  end

  def capture_family(name, actor, path, locale: 'en', status: 200)
    Rails.cache.clear
    reset!
    sign_in actor.reload if actor
    path = "#{path}#{path.include?('?') ? '&' : '?'}locale=#{locale}"
    get path, headers: { 'Accept' => 'text/html' }
    expect(response.status).to eq(status), "#{name}: expected #{status}, got #{response.status}"
    doc = Nokogiri::HTML5(response.body)
    html = family_document(doc)
    raise "#{name} contains a JWT-shaped value" if html.match?(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./)

    data = { 'path' => path, 'locale' => locale, 'now' => now.iso8601, 'actor_id' => actor&.id,
             'self_hosted' => DawarichSettings.self_hosted?, 'status' => response.status,
             'location' => response.headers['Location'], 'content_type' => response.media_type,
             'flash' => flash.to_hash, 'title' => doc.at_css('title')&.text,
             'forms' => family_controls(doc), 'frames' => doc.css('turbo-frame').map { |frame| frame['id'] },
             'links' => doc.css('[data-turbo-method], a[data-method]').map do |link|
               { 'href' => link['href'], 'method' => link['data-turbo-method'] || link['data-method'] }
             end,
             'session' => { 'user_return_to' => session[:user_return_to] },
             'actors' => family_actors, 'rows' => family_rows }
    File.write(dir.join("#{name}.html"), html)
    File.write(dir.join("#{name}.json"), "#{Oj.dump(data, mode: :strict, float_precision: 0, indent: 2)}\n")
    sign_out actor if actor
    { 'html' => html, 'state' => data }
  end

  def capture_family_sharing_stream(actor, locale)
    reset!
    sign_in actor.reload
    get '/family', params: { locale: }, headers: { 'Accept' => 'text/html' }
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    patch '/family/location_sharing',
          params: { enabled: 'false', authenticity_token: token, locale: },
          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response.status).to eq(200)
    doc = Nokogiri::HTML5.fragment(response.body)
    doc.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
    expect(doc.css('turbo-stream').map { |stream| stream['target'] })
      .to include("location-sharing-#{actor.id}", 'family-navbar-indicator', 'family-getting-started-slot')
    File.write(dir.join("sharing_toggle_#{locale}.stream.html"), doc.to_html)
    sign_out actor
  end
end
