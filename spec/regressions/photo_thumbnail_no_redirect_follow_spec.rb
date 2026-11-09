# frozen_string_literal: true

require 'rails_helper'

# Regression: the server-side thumbnail fetch must not follow redirects, so a
# save-time-validated integration host cannot 302 the request into internal space.
RSpec.describe 'Photos::Thumbnail does not follow redirects' do
  let(:user) { create(:user) }

  before do
    allow(user).to receive(:settings).and_return(
      'immich_url' => 'https://photos.example.com',
      'immich_api_key' => 'k',
      'immich_skip_ssl_verification' => false
    )
  end

  it 'passes follow_redirects: false to HTTParty' do
    expect(HTTParty).to receive(:get)
      .with(anything, hash_including(follow_redirects: false))
      .and_return('thumb')

    Photos::Thumbnail.new(user, 'immich', 'asset-1').call
  end
end
