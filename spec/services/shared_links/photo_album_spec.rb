# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::PhotoAlbum do
  subject(:album) { described_class.new(link) }

  let(:user) { create(:user, settings: { 'immich_url' => 'https://immich.example.com/' }) }
  let(:settings) do
    {
      'photo_album_id' => 'album-123',
      'photo_album_name' => 'Summer',
      'immich_shared_link_id' => 'shared-123',
      'immich_shared_link_slug' => 'summer-public'
    }
  end
  let(:link) { create(:shared_link, user:, settings:) }

  it 'derives a public shared-link photo URL without an Immich request' do
    expect(album.photo_url('asset-456'))
      .to eq('https://immich.example.com/s/summer-public/photos/asset-456')
  end

  it 'does not expose a link when no Immich shared link was selected' do
    settings.delete('immich_shared_link_slug')

    expect(album.photo_url('asset-456')).to be_nil
  end

  it 'does not expose links for an invalid Immich URL' do
    user.update!(settings: user.settings.merge('immich_url' => 'javascript:alert(1)'))

    expect(album.photo_url('asset-456')).to be_nil
  end

  it 'does not fall back to a private album URL for an invalid photo id' do
    expect(album.photo_url('not/a/valid/id')).to be_nil
  end
end
