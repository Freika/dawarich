# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Homes', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'creates the Home and answers with a Turbo Stream' do
    expect { post homes_path, params: { latitude: 52.52, longitude: 13.405 }, as: :turbo_stream }
      .to change(user.homes, :count).by(1)
    expect(response.media_type).to eq(Mime[:turbo_stream])
    expect(response.body).to include('flash-messages')
  end

  it 'refuses coordinates that are missing or out of range' do
    [{ latitude: '', longitude: '' }, { latitude: 91, longitude: 0 }, { latitude: 0, longitude: 181 },
     { latitude: 'abc', longitude: 0 }].each do |params|
      post homes_path, params:, as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include(I18n.t('trip_detection.onboarding.invalid_location'))
    end
    expect(user.homes).to be_empty
    expect(user.places).to be_empty
  end

  it 'creates nothing for a user who already has a Home' do
    create(:home, user:)
    expect { post homes_path, params: { latitude: 48.137, longitude: 11.575 }, as: :turbo_stream }
      .not_to(change { [user.homes.count, user.places.count] })
    expect(response.media_type).to eq(Mime[:turbo_stream])
    expect(response.body).to include(I18n.t('trip_detection.onboarding.home_exists'))
  end

  describe 'the home screen of the onboarding modal' do
    it 'is offered to a user without a Home' do
      get map_path
      expect(response.body).to include('data-onboarding-modal-target="homeScreen"')
    end

    it 'does not start its map until the screen is shown' do
      get map_path
      expect(response.body).not_to include('data-controller="place-location"')
    end

    it 'is reached from the import screen too' do
      get map_path
      import_screen = Nokogiri::HTML(response.body).at_css('[data-onboarding-modal-target="importScreen"]')
      expect(import_screen.at_css('[data-action="onboarding-modal#finish"]').text.strip)
        .to eq(I18n.t('trip_detection.onboarding.continue'))
    end

    it 'is left out for a user who has a Home' do
      create(:home, user:)
      get map_path
      expect(response.body).to include('data-onboarding-modal-has-home-value="true"')
      expect(response.body).not_to include('data-onboarding-modal-target="homeScreen"')
    end
  end

  it 'requires a signed-in user' do
    sign_out user
    post homes_path, params: { latitude: 52.52, longitude: 13.405 }
    expect(response).not_to have_http_status(:success)
  end
end
