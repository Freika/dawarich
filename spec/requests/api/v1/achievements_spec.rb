# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mobile achievements API', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:earned_at) { '2026-09-01T12:00:00Z' }
  let!(:exploration) do
    create(:achievement_progress, user: user, achievement_key: 'exploration',
                                  state: { 'earned' => { 'FR' => earned_at, 'DE-BE' => earned_at } })
  end

  before do
    allow_any_instance_of(Achievements::RegionSilhouettes).to receive(:call).and_return({})
    allow(Achievements::RegionSilhouettes).to receive(:collection).and_return(nil)
  end

  it 'requires API authentication without accepting a web session' do
    sign_in user
    get '/api/v1/achievements'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'reports lifetime counts and roots without writing celebration or claiming events' do
    event = Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'FR')
    before_state = exploration.state.deep_dup
    get '/api/v1/achievements', headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['summary']).to include('earned_countries' => 1, 'earned_subdivisions' => 1)
    expect(body['collections'].map { |card| card['key'] }).to include('continent_europe', 'country_aq')
    expect(body['collections'].map { |card| card['kind'] }).not_to include('region_set')
    expect(body['threshold_minutes']).to eq(user.safe_settings.min_minutes_spent_in_city)
    expect(exploration.reload.state).to eq(before_state)
    expect(event.reload.claim_token).to be_nil
  end

  it 'supports existing API-key clients and advertises mobile support' do
    get '/api/v1/users/me', params: { api_key: user.api_key }
    expect(response.parsed_body['features']['achievements']).to be true
    get '/api/v1/achievements', params: { api_key: user.api_key }
    expect(response).to have_http_status(:ok)
  end

  it 'keeps account data separate and applies the pending-payment API gate' do
    other = create(:user)
    get '/api/v1/achievements', headers: { 'Authorization' => "Bearer #{other.api_key}" }
    expect(response.parsed_body['summary']).to include('earned_countries' => 0, 'earned_subdivisions' => 0)
    user.update!(status: :pending_payment)
    get '/api/v1/achievements', headers: headers
    expect(response).to have_http_status(:payment_required)
  end

  it 'paginates only after filtering the full collection' do
    get '/api/v1/achievements/continent_europe', headers: headers
    first = response.parsed_body
    expect(first['cards'].size).to eq(12)
    expect(first['pagination']['total_count']).to be > 12
    get '/api/v1/achievements/continent_europe', params: { page: 2 }, headers: headers
    second = response.parsed_body
    expect(second['pagination']['current_page']).to eq(2)
    expect(first['cards'].map { |card| card['key'] } & second['cards'].map { |card| card['key'] }).to eq([])
  end

  it 'keeps an earned country unlocked even before subdivision progress and searches before pagination' do
    exploration.update!(state: { 'earned' => { 'DE' => earned_at } })
    get '/api/v1/achievements/continent_europe', params: { q: 'germany', status: 'in_progress' }, headers: headers
    body = response.parsed_body
    expect(body['cards'].size).to eq(1)
    expect(body['pagination']).to include('total_count' => 1, 'per_page' => 12)
    expect(body['cards'].first).to include('key' => 'country_de', 'code' => 'DE', 'locked' => false,
                                           'completed' => false, 'earned_count' => 0,
                                           'browse_key' => 'country_de', 'silhouette' => nil)
  end

  it 'returns earned subdivision leaf cards and their stable identifiers' do
    get '/api/v1/achievements/country_de', params: { status: 'unlocked' }, headers: headers
    expect(response.parsed_body['cards']).to contain_exactly(include('key' => 'DE-BE', 'kind' => 'subdivision',
                                                                     'browse_key' => nil, 'share_key' => nil,
                                                                     'earned_count' => 1, 'earned_at' => earned_at))
  end

  it 'returns visible SVG geometry and preserves the completion timestamp' do
    shape = { path: 'M 0 0 L 1 0 L 1 1 Z', viewbox: '0 0 1 1' }
    allow_any_instance_of(Achievements::RegionSilhouettes).to receive(:call).and_return('AQ' => shape)
    exploration.update!(state: { 'earned' => { 'AQ' => earned_at } })
    get '/api/v1/achievements/country_aq', headers: headers
    expect(response.parsed_body['collection']).to include('silhouette' => shape.stringify_keys,
                                                          'completed' => true, 'percent' => 100,
                                                          'earned_count' => 1, 'target' => 1,
                                                          'earned_at' => earned_at)
  end

  it 'uses chronological completion order across timestamp offsets' do
    definition = Achievements::Registry.find('country_de')
    earned = definition.region_codes.index_with { earned_at }
    earned[definition.region_codes[-2]] = '2026-09-02T01:00:00+04:00'
    earned[definition.region_codes[-1]] = '2026-09-01T23:00:00Z'
    exploration.update!(state: { 'earned' => earned })
    get '/api/v1/achievements/country_de', headers: headers
    expect(response.parsed_body['collection']['earned_at']).to eq('2026-09-01T23:00:00Z')
  end

  it 'hydrates only the visible countries after a search' do
    shapes = instance_double(Achievements::RegionSilhouettes, call: {})
    expect(Achievements::RegionSilhouettes).to receive(:new).with(level: :country, codes: ['FR']).and_return(shapes)
    get '/api/v1/achievements/continent_europe', params: { q: 'france' }, headers: headers
    expect(response).to have_http_status(:ok)
  end

  it 'supports flat orphan countries without a redirect or child loop' do
    get '/api/v1/achievements/country_aq', headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['collection']).to include('browse_key' => nil, 'parent_key' => nil)
    expect(response.parsed_body['cards']).to eq([])
  end

  it 'rejects unknown keys, hidden world tiers, and invalid filters' do
    get '/api/v1/achievements/missing', headers: headers
    expect(response).to have_http_status(:not_found)
    hidden = Achievements::Registry.all.find { |definition| definition.kind == 'region_set' }
    get "/api/v1/achievements/#{hidden.key}", headers: headers
    expect(response).to have_http_status(:not_found)
    get '/api/v1/achievements/continent_europe', params: { page: '-1' }, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    get '/api/v1/achievements/continent_europe', params: { status: 'anything' }, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'requires an explicit boolean and isolates idempotent sharing to this account' do
    other = create(:user)
    other_carrier = create(:achievement_progress, user: other, achievement_key: 'country_fr')
    patch '/api/v1/achievements/country_fr/sharing', params: { enabled: 'false' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    2.times do
      patch '/api/v1/achievements/country_fr/sharing', params: { enabled: true }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('enabled' => true)
    end
    uuid = response.parsed_body['uuid']
    expect(response.parsed_body['url']).to include(uuid)
    expect(other_carrier.reload.sharing_enabled).to be false
    patch '/api/v1/achievements/country_fr/sharing', params: { enabled: false }, headers: headers, as: :json
    expect(response.parsed_body).to include('enabled' => false, 'url' => nil, 'uuid' => uuid)
  end

  it 'claims structured cards, coordinates leases with web, resumes, and acknowledges once' do
    event = Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'FR')
    post '/api/v1/achievements/unlocks/next', headers: headers, as: :json
    body = response.parsed_body
    expect(body).to include('id' => event.id, 'remaining' => 1)
    expect(body['card']).to include('key' => 'country_fr', 'locked' => false)
    expect(body).not_to have_key('html')
    expect(Achievements::UnlockDeck.new(user).claim).to eq(:busy)
    post '/api/v1/achievements/unlocks/next', headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    post '/api/v1/achievements/unlocks/next',
         params: { claim_token: body['token'], batch_end_id: body['batch_end_id'] }, headers: headers, as: :json
    expect(response.parsed_body['id']).to eq(event.id)
    2.times do
      post "/api/v1/achievements/unlocks/#{event.id}/seen",
           params: { claim_token: body['token'] }, headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
    end
    post '/api/v1/achievements/unlocks/next', headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
  end

  it 'distinguishes a country visit unlock from a completed subdivision collection' do
    exploration.update!(state: { 'earned' => { 'DE' => earned_at } })
    Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'DE')
    post '/api/v1/achievements/unlocks/next', headers: headers, as: :json
    expect(response.parsed_body['card']).to include('key' => 'country_de', 'locked' => false,
                                                    'completed' => false, 'percent' => 0, 'earned_count' => 0,
                                                    'earned_at' => nil)
  end

  it 'reports completed set unlock progress with the last award timestamp' do
    definition = Achievements::Registry.find('country_de')
    exploration.update!(state: { 'earned' => definition.region_codes.index_with { earned_at } })
    Achievements::UnlockEvent.create!(user: user, kind: 'set', key: definition.key)
    post '/api/v1/achievements/unlocks/next', headers: headers, as: :json
    expect(response.parsed_body['card']).to include('key' => definition.key, 'locked' => false,
                                                    'completed' => true, 'percent' => 100,
                                                    'earned_count' => definition.target, 'target' => definition.target,
                                                    'earned_at' => earned_at)
  end

  it 'keeps subdivision unlock counts and timestamps consistent with the durable event' do
    event = Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'DE-BY')
    post '/api/v1/achievements/unlocks/next', headers: headers, as: :json
    expect(response.parsed_body['card']).to include('kind' => 'subdivision', 'completed' => true,
                                                    'percent' => 100, 'earned_count' => 1, 'target' => 1,
                                                    'earned_at' => event.created_at.utc.iso8601)
  end

  it 'skips obsolete unlock definitions and protects ownership and batch boundaries' do
    other = create(:user)
    foreign = Achievements::UnlockEvent.create!(user: other, kind: 'geography', key: 'FR', claim_token: 'a' * 32)
    post "/api/v1/achievements/unlocks/#{foreign.id}/seen",
         params: { claim_token: 'a' * 32 }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    obsolete = Achievements::UnlockEvent.create!(user: user, kind: 'set', key: 'removed_set')
    first = Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'FR')
    last = Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'DE')
    post '/api/v1/achievements/unlocks/next', headers: headers, as: :json
    expect(response.parsed_body['id']).to eq(first.id)
    expect(obsolete.reload.seen_at).to be_present
    post '/api/v1/achievements/unlocks/dismiss', params: { batch_end_id: first.id }, headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(first.reload.seen_at).to be_present
    expect(last.reload.seen_at).to be_nil
    expect(foreign.reload.seen_at).to be_nil
    post '/api/v1/achievements/unlocks/dismiss', params: { batch_end_id: '-1' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end
end
