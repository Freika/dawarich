# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Immich enrichment confirmation' do
  let(:user) { create(:user, settings: { 'immich_url' => 'http://immich.test', 'immich_api_key' => 'test-key' }) }
  let(:assets) { [{ 'immich_asset_id' => 'asset-1', 'latitude' => 52.52, 'longitude' => 13.405 }] }

  it 'does not claim that an accepted asynchronous update has been saved' do
    stub_request(:put, 'http://immich.test/api/assets/asset-1')
      .to_return(status: 200, body: '{}', headers: { 'content-type' => 'application/json' })

    result = Immich::EnrichPhotos.new(user, assets).call

    expect(result).to include(enriched: 0, pending: 1, failed: 0)
  end
end

RSpec.describe 'Immich result notification rendering', type: :request do
  let(:user) { create(:user) }
  let!(:notification) { create(:notification, user:, title: 'Checking Immich updates', content: 'Pending') }

  it 'keeps the detail card distinct from its navbar item' do
    sign_in user
    get notifications_path
    expect(Nokogiri::HTML(response.body).css("#navbar_notification_#{notification.id}").size).to eq(1)
    get notification_path(notification)
    html = Nokogiri::HTML(response.body)

    expect(html.css("#detail_notification_#{notification.id}").size).to eq(1)
    expect(html.css("#navbar_notification_#{notification.id}").size).to be <= 1
    expect(html.at_css("#detail_notification_#{notification.id}").text).to include('Pending')
  end

  it 'broadcasts the full result to the detail card after it has been read' do
    notification.update!(read_at: Time.current)
    expect do
      notification.update_with_broadcast!(content: 'Check XMP write permissions', kind: :warning, read_at: nil)
    end.to have_broadcasted_to("#{user.to_gid_param}:notifications").with(
      a_string_including("target=\"detail_notification_#{notification.id}\"", 'Check XMP write permissions')
    )
    expect(notification.reload).not_to be_read
  end
end
