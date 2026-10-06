# frozen_string_literal: true

module StatsClosureFixtures
  def capture_q_commands
    user = reader(5290)
    no_geocoding
    sign_in user
    get '/stats'
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    headers = { 'X-CSRF-Token' => token }
    q06 = %w[1 01 all 0 13].map do |month|
      get '/stats'
      clear_enqueued_jobs
      put "/stats/2024/#{month}/update", headers: headers
      q_result(month).merge(jobs: enqueued_jobs.map { _1[:args] })
    end
    write_json(fixtures.join('stats/a12f3a-q06.json'), q06)
    create(:point, user:, timestamp: Time.utc(2024, 3, 5).to_i)
    create(:point, user:, timestamp: Time.utc(2024, 4, 5).to_i)
    clear_enqueued_jobs
    get '/stats'
    put '/stats/update_all', headers: headers
    write_json(fixtures.join('stats/a12f3a-q07.json'), q_result('update_all').merge(jobs: enqueued_jobs.map do
      _1[:args]
    end))

    stat(52_901, user, 2024, 3, 1000)
    q09 = %w[2024 2024tail 1969 2026 2023].map do |year|
      get '/stats'
      clear_enqueued_jobs
      post '/digests', params: { year: }, headers: headers
      q_result(year).merge(jobs: enqueued_jobs.map { _1[:args] })
    end
    write_json(fixtures.join('stats/a12f3a-q09.json'), q09)

    digest(52_902, user, 2024)
    q10 = [2024, 2024].map do |year|
      get '/stats'
      delete "/digests/#{year}", headers: headers
      q_result(year).merge(remaining: user.digests.yearly.where(year:).count)
    end
    write_json(fixtures.join('stats/a12f3a-q10.json'), q10)
    sign_out user
    capture_q_reads
  end

  def capture_q_reads
    user = reader(5292)
    no_geocoding
    older = stat(52_921, user, 2024, 3, 1000, updated_at: now - 2.days)
    stat(52_922, user, 2024, 4, 9000, updated_at: now - 1.day)
    stat(52_923, user, 2023, 7, 2000)
    sign_in user
    q01 = [true, false].map do |self_hosted|
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      user.update_columns(plan: User.plans[:lite])
      get '/stats'
      action = response.request.env.fetch('action_controller.instance')
      index = action.instance_variable_get(:@year_distances)
      get '/stats/2024'
      action = response.request.env.fetch('action_controller.instance')
      { self_hosted:, index_distances: index, year_distances: action.instance_variable_get(:@year_distances),
        scoped_months: action.instance_variable_get(:@stats).pluck(:month) }
    end
    write_json(fixtures.join('stats/a12f3a-q01.json'), q01)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    user.update_columns(plan: User.plans[:pro])
    older.update_columns(daily_distance: nil)
    Stat.where(user:).where.not(id: older.id).delete_all
    q02 = [nil, { '1' => 1000 }, [[1, 1000]]].map do |daily|
      older.update_columns(daily_distance: daily)
      q_attempt(daily) { get '/stats/2024/3' }
    end
    write_json(fixtures.join('stats/a12f3a-q02.json'), q02)
    older.update_columns(daily_distance: nil)
    q03 = [{ year: ['2024'] }, { year: '2024' }].map do |params|
      q_attempt(params) { get '/insights', params: }
    end
    older.update_columns(daily_distance: [[1, 1000]])
    extra = stat(52_925, user, 2024, 4, 1000)
    get '/insights/details?year=2024'
    action = response.request.env.fetch('action_controller.instance')
    q03 << { input: { year: '2024' }, status: response.status,
selected_month: action.instance_variable_get(:@selected_month) }
    write_json(fixtures.join('stats/a12f3a-q03.json'), q03)
    extra.delete
    q04 = %w[cold stale].map do |state|
      user.digests.delete_all if state == 'cold'
      user.digests.update_all(distance: 9, travel_patterns: {}, updated_at: now - 3.days) if state == 'stale'
      Rails.cache.clear
      get '/insights/details?year=2024&month=3'
      { state:, status: response.status, digests: user.digests.order(:period_type).map do
        _1.attributes.slice(*%w[year month period_type distance travel_patterns monthly_distances])
      end }
    end
    write_json(fixtures.join('stats/a12f3a-q04.json'), q04)
    q05 = [true, false].map do |self_hosted|
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      get '/insights/details?year=2024&month=3',
          headers: { 'Turbo-Frame' => 'insights_details', 'Accept' => 'text/html' }
      { self_hosted:, status: response.status, framed: response.body.include?('<turbo-frame id="insights_details">'),
cache_control: response.headers['Cache-Control'] }
    end
    write_json(fixtures.join('stats/a12f3a-q05.json'), q05)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    user.digests.delete_all
    row = digest(52_924, user, 2024)
    q08 = [{}, { 'country' => 'Germany' }].map do |toponyms|
      row.update_columns(toponyms:)
      q_attempt(toponyms) { get '/digests/2024' }
    end
    [{ toponyms: [{ 'country' => nil, 'cities' => [] }] },
     { toponyms: [], first_time_visits: { 'countries' => 'Germany' } },
     { toponyms: [], first_time_visits: {},
time_spent_by_location: { 'countries' => [{ 'name' => 'Germany', 'minutes' => 'oops' }] } }].each do |attrs|
      row.update_columns(first_time_visits: {}, time_spent_by_location: {})
      row.update_columns(attrs)
      q08 << q_attempt(attrs) { get '/digests/2024' }.merge(attributes: true)
    end
    write_json(fixtures.join('stats/a12f3a-q08.json'), q08)
    sign_out user
    capture_q_sharing
  end

  def capture_q_sharing
    user = reader(5293)
    no_geocoding
    month = stat(52_931, user, 2024, 3, 1000, daily_distance: [[1, 1000]])
    year = digest(52_932, user, 2024, toponyms: [toponym('Germany', 'Berlin')],
                  first_time_visits: { 'countries' => ['Germany'], 'cities' => ['Berlin'] },
                  monthly_distances: { '3' => 1000 },
                  time_spent_by_location: { 'countries' => [{ 'name' => 'Germany', 'minutes' => 1000 }] })
    sign_in user
    get '/stats'
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    headers = { 'X-CSRF-Token' => token, 'Accept' => 'application/json' }
    [[11, year, '/digests/2024/sharing'], [13, month, '/stats/2024/3/sharing']].each do |task, row, path|
      cases = [%w[1 1h], %w[1 12h], %w[1 24h], %w[1 1w], %w[1 1m], %w[1 invalid], ['0', nil],
               ['true', nil]].map do |enabled, expiration|
        params = { enabled: }.tap { _1[:expiration] = expiration unless expiration.nil? }
        patch path, params:, headers: headers
        { params:, status: response.status, body: JSON.parse(response.body), settings: row.reload.sharing_settings,
          uuid: row.sharing_uuid }
      end
      write_json(fixtures.join("stats/a12f3a-q#{task}.json"), cases)
    end
    sign_out user
    [[12, year, 'digest', 'div.max-w-xl'],
     [14, month, 'month', 'div.container.mx-auto.px-4.py-8']].each do |task, row, kind, selector|
      cases = %w[full partial expired disabled].map do |state|
        user.update_columns(plan: User.plans[state == 'partial' ? :lite : :pro])
        allow(DawarichSettings).to receive(:self_hosted?).and_return(state != 'partial')
        row.enable_sharing!(expiration: '1h')
        if state == 'expired'
          row.update_columns(sharing_settings: row.sharing_settings.merge('expires_at' => (now - 1).iso8601))
        end
        row.disable_sharing! if state == 'disabled'
        get "/shared/#{kind}/#{row.sharing_uuid}"
        fragment = Nokogiri::HTML5(response.body).at_css(selector)&.to_html
        { state:, uuid: row.sharing_uuid, status: response.status, location: response.location&.delete_prefix('http://www.example.com'),
          html: fragment, cache_control: response.headers['Cache-Control'] }
      end
      if task == 14
        %w[UTC Berlin].each do |zone|
          user.update_columns(settings: user.settings.merge('timezone' => zone), plan: User.plans[:pro])
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
          row.enable_sharing!(expiration: '1h')
          get "/shared/#{kind}/#{row.sharing_uuid}"
          cases << { state: "timezone_#{zone}", owner_settings: user.settings, uuid: row.sharing_uuid,
                     status: response.status, html: Nokogiri::HTML5(response.body).at_css(selector)&.to_html,
                     cache_control: response.headers['Cache-Control'] }
        end
      end
      write_json(fixtures.join("stats/a12f3a-q#{task}.json"), cases)
    end
  end

  def q_attempt(input)
    yield
    { input:, status: response.status }
  rescue StandardError => e
    { input:, status: 500, exception: e.class.name }
  end

  def q_result(input)
    { input:, status: response.status, location: response.location&.delete_prefix('http://www.example.com'),
      flash: flash.to_h, body: response.body }
      .except(:body)
  end
end
