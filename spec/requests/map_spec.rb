# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map', type: :request do


  describe 'GET /index' do
    context 'when user signed in' do
      let(:user) { create(:user) }
      let(:points) do
        (1..10).map do |i|
          create(:point, user:, timestamp: 1.day.ago + i.minutes)
        end
      end

      before { sign_in user }

      it 'returns http success' do
        get map_path

        expect(response).to have_http_status(:success)
      end
    end

    context 'when user not signed in' do
      it 'returns redirects to sign in page' do
        get map_path

        expect(response).to have_http_status(302)
      end
    end
  end
end
