# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::PhotoAlbum do
  subject(:album) { described_class.new(link) }

  let(:user) { create(:user, settings: { 'immich_url' => 'https://immich.example.com/' }) }
  let(:settings) { { 'photo_album_id' => 'album-123', 'photo_album_name' => 'Summer' } }
  let(:link) { create(:shared_link, user:, settings:) }

  it 'derives album and photo links without an Immich request' do
    expect(album.album_url).to eq('https://immich.example.com/albums/album-123')
    expect(album.photo_url('asset-456')).to eq('https://immich.example.com/photos/asset-456')
  end

  it 'does not expose links when no album was selected' do
    settings.delete('photo_album_id')

    expect(album.album_url).to be_nil
    expect(album.photo_url('asset-456')).to be_nil
  end

  it 'does not expose links for an invalid Immich URL' do
    user.update!(settings: user.settings.merge('immich_url' => 'javascript:alert(1)'))

    expect(album.album_url).to be_nil
  end

  it 'falls back to the album for an invalid photo id' do
    expect(album.photo_url('not/a/valid/id')).to eq('https://immich.example.com/albums/album-123')
  end
end
