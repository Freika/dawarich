# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Exports', type: :request do
  describe 'GET /download' do
    before do
      sign_in create(:user)
    end

    it 'returns http success' do
      get '/export/download'

      expect(response).to have_http_status(:success)
    end
  end
end
