# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: achievement unlock deck', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/achievement_unlocks') }
  let(:now) { Time.utc(2026, 10, 4, 22, 30) }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  def synthetic_user(id, locale: 'en')
    create(:user, id:, email: "a10c-deck-#{id}@example.invalid", password: 'a10c-synthetic-password',
                  settings: { 'locale' => locale, 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true })
  end

  def event(user, id, key, kind: 'geography')
    Achievements::UnlockEvent.create!(id:, user:, key:, kind:, created_at: now - 1.day, updated_at: now - 1.day)
  end

  def event_row(row)
    row.reload
    { 'id' => row.id, 'user_id' => row.user_id, 'key' => row.key, 'kind' => row.kind,
      'seen_at' => row.seen_at&.utc&.iso8601(6), 'claimed_at' => row.claimed_at&.utc&.iso8601(6),
      'token_present' => row.claim_token.present?, 'created_at' => row.created_at.utc.iso8601(6),
      'updated_at' => row.updated_at.utc.iso8601(6) }
  end

  def claim_row(claim)
    return claim.to_s if claim == :busy
    return unless claim

    expect(claim.event.claim_token).to match(/\A[0-9a-f]{32}\z/)
    { 'event' => event_row(claim.event), 'remaining' => claim.remaining,
      'batch_end_id' => claim.batch_end_id, 'token_shape' => '32-lowercase-hex' }
  end

  def lease_cases
    actor = synthetic_user(42_001)
    foreign = synthetic_user(42_002)
    first = event(actor, 42_001, 'FR')
    second = event(actor, 42_002, 'DE')
    deck = Achievements::UnlockDeck.new(actor)
    claimed = deck.claim
    token = claimed.event.claim_token
    expect([claimed.event.id, claimed.remaining, claimed.batch_end_id]).to eq([first.id, 2, second.id])
    results = { 'claim' => claim_row(claimed) }
    future = event(actor, 42_003, 'IT')
    other = event(foreign, 42_004, 'FR')
    results['active_outside_batch'] = claim_row(deck.claim(batch_end_id: first.id - 1))
    expect(results['active_outside_batch']).to eq('busy')
    travel_to(now + 45.seconds)
    results['inclusive_45'] = claim_row(deck.claim)
    expect(results['inclusive_45']).to eq('busy')
    resumed = deck.claim(resume_token: token, batch_end_id: second.id)
    expect(resumed.event.claim_token == token).to be(true)
    expect([resumed.event.id, resumed.remaining, resumed.batch_end_id]).to eq([first.id, 2, second.id])
    expect(first.reload.updated_at).to eq(now + 45.seconds)
    results['resume'] = claim_row(resumed)
    resumed_outside = deck.claim(resume_token: token, batch_end_id: first.id - 1)
    expect([resumed_outside.event.id, resumed_outside.remaining, resumed_outside.batch_end_id])
      .to eq([first.id, 0, first.id - 1])
    results['resume_outside_batch'] = claim_row(resumed_outside)
    travel_to(now + 90.seconds)
    expect(deck.claim).to eq(:busy)
    travel_to(now + 91.seconds)
    reclaimed = deck.claim(batch_end_id: second.id)
    expect(reclaimed.event.claim_token == token).to be(false)
    expect(reclaimed.event.id).to eq(first.id)
    results['expired_46'] = claim_row(reclaimed)
    reclaimed_token = reclaimed.event.claim_token
    timestamp = first.reload.updated_at
    ack = { 'blank' => deck.acknowledge(id: first.id, token: ''),
            'wrong' => deck.acknowledge(id: first.id, token: token),
            'foreign' => deck.acknowledge(id: other.id, token: reclaimed_token),
            'own' => deck.acknowledge(id: first.id, token: reclaimed_token),
            'repeat_different' => deck.acknowledge(id: first.id, token: 'different-nonblank') }
    expect(ack).to eq('blank' => false, 'wrong' => false, 'foreign' => false, 'own' => true,
                      'repeat_different' => true)
    expect(first.reload.updated_at).to eq(timestamp)
    expect([first.claim_token, first.claimed_at]).to eq([nil, nil])
    results['acknowledgment'] = ack.merge('row' => event_row(first))
    next_claim = deck.claim(batch_end_id: second.id)
    expect([next_claim.event.id, next_claim.remaining, next_claim.batch_end_id]).to eq([second.id, 1, second.id])
    results['bounded_next'] = claim_row(next_claim)
    second_timestamp = second.reload.updated_at
    other_before = event_row(other)
    future_before = event_row(future)
    deck.dismiss_through(batch_end_id: second.id)
    expect(second.reload.updated_at).to eq(second_timestamp)
    expect([second.claim_token, second.claimed_at]).to eq([nil, nil])
    expect(event_row(other)).to eq(other_before)
    expect(event_row(future)).to eq(future_before)
    results['dismissed_ids'] = [second].select { |row| row.reload.seen_at }.map(&:id)
    results['pending_ids'] = [future, other].select { |row| row.reload.seen_at.nil? }.map(&:id)
    results['rows'] = [first, second, future, other].map { |row| event_row(row) }
    expect(deck.claim(batch_end_id: first.id - 1)).to be_nil
    expect(Achievements::UnlockDeck.new(synthetic_user(42_003)).claim).to be_nil
    results['http'] = boundary_http_cases(actor)
    results
  end

  def login(actor)
    reset!
    sign_in actor
    get settings_background_jobs_path, params: { locale: actor.locale }
    expect(response.status).to eq(200)
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
  end

  def post_unlock(path, token, params = {}, form: false)
    payload = form ? params.merge(authenticity_token: token) : params
    raw = form ? URI.encode_www_form(payload) : ActiveSupport::JSON.encode(payload)
    headers = { 'Content-Type' => form ? 'application/x-www-form-urlencoded' : 'application/json',
                'Accept' => 'application/json' }
    headers['X-CSRF-Token'] = token unless form
    public_send(:post, path, params: raw, headers: headers)
    data = response.media_type == 'application/json' && response.body.present? ? response.parsed_body : nil
    expect(data['token']).to match(/\A[0-9a-f]{32}\z/) if data&.key?('token')
    { 'path' => path, 'status' => response.status,
      'headers' => response.headers.slice('Content-Type', 'Cache-Control'),
      'json' => data&.except('token'), 'empty_body' => response.body.empty?, 'form' => form }
  end

  def boundary_http_cases(actor)
    token = login(actor)
    invalid = ['0', '-1', '+1', '01', '1.0', ' 1', 'abc', '9223372036854775808', '10000000000000000000']
    rows = invalid.flat_map do |value|
      seen = post_unlock("/achievements/unlocks/#{ERB::Util.url_encode(value)}/seen", token,
                         { claim_token: 'synthetic-wrong' })
      dismiss = post_unlock('/achievements/unlocks/dismiss', token, { batch_end_id: value })
      expect([seen['status'], dismiss['status']]).to eq([value == '1.0' ? 404 : 400, 400]), "input id #{value}"
      [seen.merge('input_id' => value), dismiss.merge('input_id' => value)]
    end
    [nil, '', ' '].each do |value|
      row = post_unlock('/achievements/unlocks/42003/seen', token, { claim_token: value })
      expect(row['status']).to eq(400)
      rows << row.merge('blank_input' => value)
    end
    row = post_unlock('/achievements/unlocks/9223372036854775807/seen', token,
                      { claim_token: 'synthetic-wrong' })
    expect(row['status']).to eq(409)
    rows << row
    row = post_unlock('/achievements/unlocks/42001/seen', token, { claim_token: 'different-nonblank' }, form: true)
    expect(row['status']).to eq(204)
    rows << row
    row = post_unlock('/achievements/unlocks/42004/seen', token, { claim_token: 'synthetic-wrong' })
    expect(row['status']).to eq(409)
    rows << row
    row = post_unlock('/achievements/unlocks/dismiss', token, { batch_end_id: '42002' }, form: true)
    expect(row['status']).to eq(204)
    rows << row
    empty_actor = synthetic_user(42_004)
    empty_token = login(empty_actor)
    row = post_unlock('/achievements/unlocks/next', empty_token)
    expect([row['status'], row['empty_body']]).to eq([204, true])
    rows << row
    rows
  end

  def shapes
    Rails.cache.clear
    square = 'MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))'
    create(:country, id: 42_501, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU', geom: square)
    create(:country, id: 42_502, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: square)
    create(:region, id: 42_503, code: 'DE-BY', geom: square)
  end

  def card_cases
    shapes
    state = { 'earned' => { 'FR' => now.iso8601, 'DE' => now.iso8601, 'DE-BY' => now.iso8601 } }
    cards = %w[en de es fr pl ca zh].each_with_index.flat_map do |locale, index|
      actor = synthetic_user(42_101 + index, locale:)
      progress = create(:achievement_progress, id: actor.id, user: actor, achievement_key: 'exploration', state:)
      snapshot = progress.reload.state
      scenarios = [%w[continent continent_europe set], %w[country_set country_de set],
                   %w[visited_country DE geography], %w[flat_country FR geography],
                   %w[subdivision DE-BY geography], %w[hidden border_hopper set],
                   %w[missing missing_definition set]]
      scenarios.each_with_index.map do |(name, key, kind), offset|
        row = event(actor, 42_101 + index * 20 + offset, key, kind:)
        row.update_columns(created_at: now)
        card_state = if name == 'country_set'
                       { 'earned' => Achievements::Registry.find('country_de').region_codes.index_with { now.iso8601 } }
                     else
                       state
                     end
        I18n.with_locale(locale) do
          card = Achievements::UnlockCardPresenter.new(event: row, state: card_state, timezone: 'Europe/Berlin').call
          record = { 'name' => "#{locale}_#{name}", 'locale' => locale, 'state' => card_state,
                     'event' => event_row(row), 'timezone' => 'Europe/Berlin',
                     'card' => card && { 'name' => card.name, 'path' => card.path, 'attributes' => card.attributes } }
          if %w[hidden missing].include?(name)
            expect(card).to be_nil
          else
            expect(card).not_to be_nil
            expect(card.path).to eq('/achievements/continent_europe?q=France#collection') if name == 'flat_country'
            expect(card.path).to eq('/achievements/country_de?q=Bavaria#collection') if name == 'subdivision'
            if name == 'visited_country'
              expect(card.attributes).to include(name: 'Germany', description: nil, locked: false,
                                                 earned_label: I18n.t('achievements.cards.status.visited'))
            end
            if name == 'subdivision'
              date = I18n.l(Date.new(2026, 10, 5), format: I18n.t('achievements.cards.date_format'))
              expect(card.attributes[:earned_label]).to eq(I18n.t('achievements.cards.status.unlocked_on', date:))
              expect(card.attributes[:silhouette]).to be_present
            end
          end
          expect(progress.reload.state).to eq(snapshot)
          record
        end
      end
    end
    { 'cards' => cards, 'http' => visible_http_cases(state) }.merge(invisible_cases)
  end

  def visible_http_cases(state)
    %w[en de].each_with_index.flat_map do |locale, index|
      actor = synthetic_user(42_201 + index, locale:)
      create(:achievement_progress, id: actor.id, user: actor, achievement_key: 'exploration', state:)
      first = event(actor, 42_301 + index * 10, 'FR')
      last = event(actor, 42_302 + index * 10, 'DE')
      token = login(actor)
      row = post_unlock('/achievements/unlocks/next', token)
      expect([row['status'], row.dig('json', 'id'), row.dig('json', 'remaining')]).to eq([200, first.id, 2])
      expect(row.dig('json', 'html')).to include('ach-unlock-back', 'ach-spectral', 'France')
      claim_token = response.parsed_body.fetch('token')
      html = row['json'].delete('html')
      save_html("#{locale}_next", html)
      results = [row.merge('name' => "#{locale}_next", 'html_file' => "#{locale}_next.html")]
      busy = post_unlock('/achievements/unlocks/next', token)
      expect([busy['status'], busy['json']]).to eq([409, { 'retry_after' => 2 }])
      results << busy.merge('name' => "#{locale}_busy")
      resumed = post_unlock('/achievements/unlocks/next', token,
                            { claim_token:, batch_end_id: last.id }, form: true)
      expect([resumed['status'], resumed.dig('json', 'id'), resumed.dig('json', 'remaining')]).to eq([200, first.id, 2])
      expect(response.parsed_body.fetch('token') == claim_token).to be(true)
      expect(resumed['json'].delete('html')).to eq(html)
      results << resumed.merge('name' => "#{locale}_resume", 'html_file' => "#{locale}_next.html")
      seen = post_unlock("/achievements/unlocks/#{first.id}/seen", token, { claim_token: })
      expect(seen['status']).to eq(204)
      results << seen.merge('name' => "#{locale}_seen")
      dismiss = post_unlock('/achievements/unlocks/dismiss', token, { batch_end_id: last.id })
      expect(dismiss['status']).to eq(204)
      results << dismiss.merge('name' => "#{locale}_dismiss")
      empty = post_unlock('/achievements/unlocks/next', token)
      expect(empty['status']).to eq(204)
      results << empty.merge('name' => "#{locale}_empty")
      results
    end
  end

  def invisible_cases
    actor = synthetic_user(42_401)
    progress = create(:achievement_progress, id: actor.id, user: actor, achievement_key: 'exploration', state: {})
    events = 11.times.map { |index| event(actor, 42_401 + index, "missing_#{index}", kind: 'set') }
    token = login(actor)
    attempts = 0
    state_reads = 0
    allow_any_instance_of(Achievements::UnlockCardPresenter).to receive(:call).and_wrap_original do |original|
      attempts += 1
      original.call
    end
    allow(Achievements::Progress).to receive(:find_by).and_wrap_original do |original, *args|
      state_reads += 1
      original.call(*args)
    end
    Flipper.disable(:achievements)
    row = post_unlock('/achievements/unlocks/next', token)
    expect([row['status'], row['empty_body'], state_reads]).to eq([204, true, 1])
    expect(events.first(10).all? { |item| item.reload.seen_at.present? }).to be(true)
    expect(progress.reload.state).to eq({})
    { 'invisible_attempts' => attempts, 'eleventh_pending' => events.last.reload.seen_at.nil?,
      'state_reads' => state_reads, 'invisible_response' => row,
      'invisible_rows' => events.map { |item| event_row(item) } }
  ensure
    Flipper.remove(:achievements)
  end

  def save_html(name, html)
    path = dir.join("#{name}.html")
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(dir)
      File.write(path, html)
    else
      expect(path.read).to eq(html)
    end
  end

  def save_json(name, cases)
    path = dir.join("#{name}.json")
    bytes = "#{Oj.dump(cases, mode: :strict, float_precision: 0, indent: 2).rstrip}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(dir)
      File.write(path, bytes)
    else
      expect(path.read).to eq(bytes)
    end
  end

  it 'captures lease resume batch and acknowledgment boundaries' do
    cases = lease_cases
    expect(cases.fetch('dismissed_ids')).to eq([42_002])
    expect(cases.fetch('pending_ids')).to eq([42_003, 42_004])
    save_json('lease', cases)
  end

  it 'captures all visible unlock cards and ten invisible attempts' do
    cases = card_cases
    expect(cases.fetch('invisible_attempts')).to eq(10)
    expect(cases.fetch('eleventh_pending')).to be(true)
    expect(cases.fetch('cards').map { |row| row.fetch('locale') }.uniq).to eq(%w[en de es fr pl ca zh])
    save_json('cards', cases)
  end
end
