# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Turbo-tracked assets', type: :request do
  def tracked_assets
    Nokogiri::HTML(response.body).css('head [data-turbo-track="reload"]').map do |node|
      "#{node['href'] || node['src'] || node['id']} #{Digest::SHA256.hexdigest(node.to_html)[0, 12]}"
    end
  end

  it 'are the same for visitors and signed-in users, so Turbo keeps the sign-out flash instead of reloading' do
    get '/'
    signed_out = tracked_assets

    sign_in create(:user)
    get '/stats'
    application_layout = tracked_assets
    get '/map/v2'
    map_layout = tracked_assets

    expect(signed_out).not_to be_empty
    expect(application_layout).to eq(signed_out)
    expect(map_layout).to eq(signed_out)
  end
end
