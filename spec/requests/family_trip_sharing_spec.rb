# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family trip sharing', type: :request do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let(:trip) { create(:trip, user: owner, name: 'Family camper trip') }
  let(:link) do
    create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                         settings: { 'audience' => 'family', 'family_id' => family.id, 'show_route' => true })
  end

  before do
    create(:family_membership, :owner, family: family, user: owner)
    create(:family_membership, family: family, user: member)
    allow_any_instance_of(Trip).to receive(:photos_by_day).and_return({})
  end

  it 'creates a family-only share from the trip sharing form' do
    sign_in owner
    post trip_share_link_path(trip), params: { shared_link: { audience: 'family', magic_phrase: 'ignored' } }

    share = owner.shared_links.last
    expect(share.settings).to include('audience' => 'family', 'family_id' => family.id)
    expect(share.magic_phrase).to be_nil
  end

  it 'does not silently create a public share when the owner has no family' do
    owner.family_membership.destroy!
    sign_in owner

    expect do
      post trip_share_link_path(trip), params: { shared_link: { audience: 'family' } }
    end.not_to change(SharedLink, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'lists family trips alongside the members own trips' do
    link
    sign_in member
    get trips_path

    expect(response.body).to include('Family camper trip', public_shared_link_path(link))
    expect(response.body).not_to include(trip.path.coordinates.to_json)
  end

  it 'does not list private or publicly shared trips as family trips' do
    link.update!(settings: {})
    sign_in member
    get trips_path

    expect(response.body).not_to include('Family camper trip')
  end

  it 'allows a family member to view the trip without revealing the owners API key' do
    sign_in member
    get public_shared_link_path(link)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Family camper trip', 'Family')
    expect(response.body).not_to include(owner.api_key)
  end

  it 'denies anonymous viewers even if they know the link' do
    get public_shared_link_path(link)
    expect(response).to have_http_status(:not_found)
  end

  it 'denies an unrelated signed-in user' do
    sign_in create(:user)
    get public_shared_link_path(link)
    expect(response).to have_http_status(:not_found)
  end

  it 'denies the unlock action to anonymous visitors' do
    post unlock_public_shared_link_path(link), params: { phrase: '' }
    expect(response).to have_http_status(:not_found)
  end

  it 'scopes the family points API to the trip dates and makes the response private' do
    inside = create(:point, user: owner, timestamp: trip.started_at.to_i + 60, reverse_geocoded_at: Time.current)
    create(:point, user: owner, timestamp: trip.ended_at.to_i + 60, reverse_geocoded_at: Time.current)
    sign_in member
    get "/api/v1/shared/#{link.id}/points"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map(&:last)).to eq([inside.timestamp])
    expect(response.headers['Cache-Control']).not_to include('public')
  end

  it 'protects every shared API through the common authorization gate' do
    %w[points trip photos].each do |endpoint|
      get "/api/v1/shared/#{link.id}/#{endpoint}"
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'does not expose coordinates when the owner excludes the route' do
    create(:point, user: owner, timestamp: trip.started_at.to_i + 60, reverse_geocoded_at: Time.current)
    link.update!(settings: link.settings.merge('show_route' => false))
    sign_in member
    get "/api/v1/shared/#{link.id}/points"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it 'applies the owners privacy zones to family routes' do
    create(:point, user: owner, timestamp: trip.started_at.to_i + 60,
                   latitude: 52.0, longitude: 13.0, reverse_geocoded_at: Time.current)
    outside = create(:point, user: owner, timestamp: trip.started_at.to_i + 120,
                            latitude: 53.0, longitude: 14.0, reverse_geocoded_at: Time.current)
    home = create(:place, user: owner, latitude: 52.0, longitude: 13.0)
    tag = create(:tag, user: owner, privacy_radius_meters: 500)
    create(:tagging, tag: tag, taggable: home)
    sign_in member
    get "/api/v1/shared/#{link.id}/points"

    expect(response.parsed_body.map(&:last)).to eq([outside.timestamp])
  end

  it 'withdraws access when the member leaves the family' do
    sign_in member
    member.family_membership.destroy!
    get "/api/v1/shared/#{link.id}/points"
    expect(response).to have_http_status(:not_found)
  end

  it 'removes revoked family shares from the list and viewer' do
    link.update!(revoked_at: Time.current)
    sign_in member
    get trips_path
    expect(response.body).not_to include('Family camper trip')
    get public_shared_link_path(link)
    expect(response).to have_http_status(:not_found)
  end

  it 'removes expired family shares from the list and API' do
    link.update_columns(expires_at: 1.minute.ago)
    sign_in member
    get trips_path
    expect(response.body).not_to include('Family camper trip')
    get "/api/v1/shared/#{link.id}/points"
    expect(response).to have_http_status(:not_found)
  end

  it 'does not transfer old shared trips when the owner joins a different family' do
    link
    owner.family_membership.destroy!
    other_family = create(:family, creator: owner)
    create(:family_membership, :owner, family: other_family, user: owner)
    sign_in member
    get public_shared_link_path(link)
    expect(response).to have_http_status(:not_found)
  end

  it 'denies access while the family subscription has lapsed' do
    link
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    family.update!(access_until: 1.day.ago)
    sign_in member
    get public_shared_link_path(link)
    expect(response).to have_http_status(:not_found)
  end

  it 'never grants edit or export access to a family member' do
    link
    sign_in member
    get edit_trip_path(trip)
    expect(response).to have_http_status(:not_found)
    post export_trip_path(trip), params: { file_format: 'gpx' }
    expect(response).not_to have_http_status(:ok)
    expect(member.exports).to be_empty
  end
end
