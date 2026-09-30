# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::RequestPhotos do
  let(:user) { create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => 'fixture' }) }
  let(:photos) do
    [
      { 'id' => 'visible', 'fileCreatedAt' => '2024-01-01T12:00:00Z', 'isArchived' => false },
      { 'id' => 'archived', 'fileCreatedAt' => '2024-01-01T12:00:00Z', 'isArchived' => true },
      { 'id' => 'archived-v2', 'fileCreatedAt' => '2024-01-01T12:00:00Z', 'visibility' => 'archive' }
    ]
  end

  before do
    stub_request(:post, 'http://immich.app/api/search/metadata').to_return(
      { status: 200, body: { assets: { items: photos } }.to_json, headers: { 'content-type' => 'application/json' } },
      { status: 200, body: { assets: { items: [] } }.to_json, headers: { 'content-type' => 'application/json' } }
    )
  end

  it 'explicitly excludes archived assets on every search page' do
    described_class.new(user).call

    expected = { 'isArchived' => false, 'visibility' => 'timeline' }
    expect(WebMock).to have_requested(:post, 'http://immich.app/api/search/metadata')
      .with { |request| JSON.parse(request.body).slice(*expected.keys) == expected }.twice
  end

  it 'drops archived assets even if the upstream includes them' do
    expect(described_class.new(user).call.pluck('id')).to eq(['visible'])
  end
end
