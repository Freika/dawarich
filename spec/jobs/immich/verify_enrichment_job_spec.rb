# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::VerifyEnrichmentJob, type: :job do
  let(:user) { create(:user, settings: { 'immich_url' => 'http://immich.test', 'immich_api_key' => 'test-key' }) }
  let(:notification) { create(:notification, user:, title: 'Checking', content: 'Pending', kind: :info) }
  let(:assets) { [{ 'immich_asset_id' => 'asset-1', 'latitude' => 52.52, 'longitude' => 13.405 }] }
  let(:url) { 'http://immich.test' }

  def metadata(id, latitude: 52.52, longitude: 13.405)
    stub_request(:get, "#{url}/api/assets/#{id}")
      .to_return(status: 200, body: { exifInfo: { latitude:, longitude: } }.to_json,
                 headers: { 'content-type' => 'application/json' })
  end

  it 'confirms coordinates returned by Immich without writing any location updates' do
    metadata('asset-1', latitude: 52.520000001)
    described_class.perform_now(notification.id, assets, url)

    expect(notification.reload).to be_info
    expect(notification.content).to include('Confirmed the saved location for 1 photo')
    expect(WebMock).not_to have_requested(:put, /immich/)
  end

  it 'explains unconfirmed writes and external-library permissions after bounded retries' do
    metadata('asset-1', latitude: nil, longitude: nil)
    perform_enqueued_jobs do
      described_class.perform_later(notification.id, assets, url)
    end

    expect(notification.reload).to be_warning
    expect(notification.content).to include('Could not confirm saved locations for 1 photos', 'read-only', 'XMP')
    expect(WebMock).to have_requested(:get, "#{url}/api/assets/asset-1").times(3)
  end

  it 'allows a delayed metadata job to complete without warning prematurely' do
    stub_request(:get, "#{url}/api/assets/asset-1").to_return(
      { status: 200, body: '{"exifInfo": {"latitude": null, "longitude": null}}' },
      { status: 200, body: '{"exifInfo": {"latitude": 52.52, "longitude": 13.405}}' }
    )
    perform_enqueued_jobs do
      described_class.perform_later(notification.id, assets, url)
    end

    expect(notification.reload).to be_info
    expect(notification.content).to include('Confirmed the saved location for 1 photo')
    expect(WebMock).to have_requested(:get, "#{url}/api/assets/asset-1").twice
  end

  it 'does not confuse missing coordinates with a requested zero coordinate' do
    metadata('asset-1', latitude: nil, longitude: nil)
    assets.first.merge!('latitude' => 0, 'longitude' => 0)
    described_class.perform_now(notification.id, assets, url, pass: 3)

    expect(notification.reload).to be_warning
  end

  it 'preserves partial success across batches and retries only unconfirmed assets' do
    batch = 21.times.map do |i|
      metadata("asset-#{i}", latitude: i.zero? ? nil : 52.52)
      assets.first.merge('immich_asset_id' => "asset-#{i}")
    end
    perform_enqueued_jobs do
      described_class.perform_later(notification.id, batch, url)
    end

    expect(notification.reload.content).to include('Confirmed saved locations for 20 photos', 'for 1 photos')
    expect(WebMock).to have_requested(:get, "#{url}/api/assets/asset-0").times(3)
    expect(WebMock).to have_requested(:get, "#{url}/api/assets/asset-20").once
  end

  it 'keeps a replayed completion in the same notification' do
    metadata('asset-1')
    id = notification.id
    expect do
      2.times { described_class.perform_now(id, assets, url) }
    end.not_to change(Notification, :count)
  end

  it 'does not query a different Immich instance after settings change' do
    user.update!(settings: user.settings.merge('immich_url' => 'http://other.test'))
    described_class.perform_now(notification.id, assets, url)

    expect(notification.reload).to be_warning
    expect(WebMock).not_to have_requested(:get, /immich|other/)
  end

  it 'ignores a deleted notification and its user' do
    described_class.perform_now(-1, assets, url)
    expect(WebMock).not_to have_requested(:get, /immich/)
  end

  [403, 500].each do |status|
    it "reports that verification could not be completed after HTTP #{status}" do
      stub_request(:get, "#{url}/api/assets/asset-1").to_return(status:)
      described_class.perform_now(notification.id, assets, url, pass: 3)
      expect(notification.reload).to be_warning
      expect(notification.content).to include('asset.read')
    end
  end

  it 'reports unconfirmed coordinates when the connection times out' do
    stub_request(:get, "#{url}/api/assets/asset-1").to_timeout
    described_class.perform_now(notification.id, assets, url, pass: 3)
    expect(notification.reload).to be_warning
  end

  ['not json', 'null', '{"exifInfo": []}'].each do |body|
    it "handles a malformed metadata response: #{body}" do
      stub_request(:get, "#{url}/api/assets/asset-1").to_return(status: 200, body:)
      described_class.perform_now(notification.id, assets, url, pass: 3)
      expect(notification.reload).to be_warning
    end
  end
end
