# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip notes remote images', type: :request do
  it 'renders notes containing a relative image URL' do
    user = create(:user)
    description = '<div>Image notes<action-text-attachment content-type="image" url="x"></action-text-attachment></div>'
    trip = create(:trip, user: user, description: description)
    sign_in user

    get trip_path(trip)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Image notes')
    expect(Nokogiri::HTML(response.body).at_css('img[src="x"]')).to be_present
  end

  it 'does not render executable image URLs or injected attributes' do
    user = create(:user)
    description = '<action-text-attachment content-type="image" url="javascript:alert(1)"></action-text-attachment>' \
                  '<action-text-attachment content-type="image" ' \
                  'url="x&quot; onerror=&quot;alert(1)"></action-text-attachment>'
    trip = create(:trip, user: user, description: description)
    sign_in user

    get trip_path(trip)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.css('img[src^="javascript:"], [onerror], a[href^="javascript:"]')).to be_empty
  end
end
