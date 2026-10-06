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
      delete "/digests/#{year}", headers: headers
      q_result(year).merge(remaining: user.digests.yearly.where(year:).count)
    end
    write_json(fixtures.join('stats/a12f3a-q10.json'), q10)
    sign_out user
  end

  def q_result(input)
    { input:, status: response.status, location: response.location&.delete_prefix('http://www.example.com'),
      flash: flash.to_h, body: response.body }
      .except(:body)
  end
end
