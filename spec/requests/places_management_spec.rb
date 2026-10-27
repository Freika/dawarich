# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Places management', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it 'renders searchable paginated rows, tag links, badges and a create link without visit N+1 queries' do
    tag = create(:tag, user:, name: 'Private home', privacy_radius_meters: 100)
    21.times do |index|
      place = create(:place, user:, name: format('Home %02d', index), tags: [tag], geofence: true)
      create(:visit, user:, place:, status: :confirmed)
    end
    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] if args.last[:sql].match?(/SELECT.*\bvisits\b/i) }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      get places_url(q: 'Home', tag_ids: [tag.id], sort: 'visit_count')
    end

    doc = Nokogiri::HTML(response.body)
    expect(response).to be_successful
    expect(doc.css('[data-testid="place-row"]').size).to eq(20)
    expect(doc.at_css('a[href="/map/v2?create_place=1"]')).to be_present
    expect(doc.css('a[href]').any? { |a| a['href'].include?("tag_ids%5B%5D=#{tag.id}") }).to be(true)
    expect(doc.at_css('[role="navigation"] a')['href']).to include('q=Home', 'sort=visit_count',
                                                                   "tag_ids%5B%5D=#{tag.id}")
    expect(response.body).to include('Geofence', 'Privacy zone', 'Private home')
    expect(queries.size).to be <= 3
    expect(queries.count { |sql| sql.include?('GROUP BY') }).to be >= 1
  end

  it 'adds and removes owned tags only on owned selected places and accepts Turbo submissions' do
    mine = create(:place, user:)
    foreign = create(:place)
    tag = create(:tag, user:)
    patch bulk_update_places_url, params: { place_ids: [mine.id, foreign.id], operation: 'add_tag', tag_id: tag.id },
                                 as: :turbo_stream
    expect(response).to have_http_status(:see_other)
    expect(mine.reload.tags).to include(tag)
    expect(foreign.reload.tags).to be_empty
    patch bulk_update_places_url, params: { place_ids: [mine.id], operation: 'remove_tag', tag_id: tag.id }
    expect(mine.reload.tags).to be_empty
  end

  it 'refuses foreign tags and invalid operations without changing places' do
    mine = create(:place, user:)
    tag = create(:tag)
    %w[add_tag invalid].each do |operation|
      patch bulk_update_places_url, params: { place_ids: [mine.id], operation:, tag_id: tag.id }
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to be_present
      expect(mine.reload.tags).to be_empty
    end
  end

  it 'deletes owned selections while retaining visits and location labels' do
    mine = create(:place, user:, name: 'Keep this label')
    foreign = create(:place)
    visit = create(:visit, user:, place: mine)

    delete bulk_destroy_places_url, params: { place_ids: [mine.id, foreign.id] }

    expect(response).to have_http_status(:see_other)
    expect(Place.exists?(mine.id)).to be(false)
    expect(foreign.reload).to be_present
    expect(visit.reload).to have_attributes(place_id: nil, location_label: 'Keep this label')
  end

  it 'merges selected owned places into the chosen survivor and ignores foreign ids' do
    survivor, first, second = create_list(:place, 3, user:)
    foreign = create(:place)
    visit = create(:visit, user:, place: second)

    post bulk_merge_places_url, params: { place_ids: [survivor.id, first.id, second.id, foreign.id],
                                         survivor_id: survivor.id }

    expect(response).to have_http_status(:see_other)
    expect(user.places).to contain_exactly(survivor)
    expect(visit.reload.place).to eq(survivor)
    expect(foreign.reload).to be_present
  end

  it 'rolls back every merge when a later duplicate has a visit conflict' do
    survivor, first, second = create_list(:place, 3, user:)
    moved = create(:visit, user:, place: first, started_at: 2.days.ago)
    started_at = 1.day.ago.change(usec: 0)
    create(:visit, user:, place: survivor, started_at:)
    create(:visit, user:, place: second, started_at:)

    post bulk_merge_places_url, params: { place_ids: [survivor.id, first.id, second.id], survivor_id: survivor.id }

    expect(response).to have_http_status(:see_other)
    expect(user.places).to contain_exactly(survivor, first, second)
    expect(moved.reload.place).to eq(first)
    expect(flash[:alert]).to include('both start')
  end

  it 'refuses a foreign or unselected survivor and empty selections' do
    mine = create(:place, user:)
    foreign = create(:place)
    [foreign.id, create(:place, user:).id].each do |survivor_id|
      post bulk_merge_places_url, params: { place_ids: [mine.id], survivor_id: }
      expect(flash[:alert]).to be_present
      expect(mine.reload).to be_present
    end
    delete bulk_destroy_places_url
    expect(flash[:alert]).to be_present
  end

  it 'renders duplicate clusters with a preselected survivor and no foreign places' do
    mine = create(:place, user:, name: 'Owned survivor')
    duplicate = create(:place, user:, name: 'Owned duplicate', source: :photon)
    foreign = create(:place, name: 'Foreign secret name')

    get places_url(view: 'duplicates')

    expect(response.body).to include(mine.name, duplicate.name, 'Possible duplicates')
    expect(response.body).not_to include(foreign.name)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('select[name="survivor_id"] option[selected]')['value']).to eq(mine.id.to_s)
    expect(doc.at_css('form')['action']).to be_present
  end

  it 'requires authentication for every collection action' do
    sign_out user
    get places_url(view: 'duplicates')
    expect(response).to redirect_to(new_user_session_path)
    patch bulk_update_places_url
    expect(response).to redirect_to(new_user_session_path)
    delete bulk_destroy_places_url
    expect(response).to redirect_to(new_user_session_path)
    post bulk_merge_places_url
    expect(response).to redirect_to(new_user_session_path)
  end
end
