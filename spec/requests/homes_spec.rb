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
    end
    expect(user.homes).to be_empty
    expect(user.places).to be_empty
  end

  describe 'the home screen of the onboarding modal' do
    it 'is offered to a user without a Home' do
      get map_path
      expect(response.body).to include('data-onboarding-modal-target="homeScreen"')
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
