# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/areas', type: :request do
  let(:user) { create(:user) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'POST /create' do
    let(:valid_params) { { name: 'Test Area', latitude: 52.52, longitude: 13.405, radius: 200 } }

    context 'without authentication' do
      it 'redirects to login' do
        post areas_url, params: valid_params, as: :turbo_stream

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when signed in' do
      before { sign_in user }

      context 'with turbo_stream format' do
        context 'with valid params' do
          it 'creates a new area' do
            expect do
              post areas_url, params: valid_params, as: :turbo_stream
            end.to change(Area, :count).by(1)
          end

          it 'returns turbo_stream replacing area-creation-data with flash' do
            post areas_url, params: valid_params, as: :turbo_stream

            expect_turbo_stream_response
            expect_turbo_stream_action('replace', 'area-creation-data')
            expect_flash_stream('Area created successfully!')
          end

          it 'includes serialized area data attributes' do
            post areas_url, params: valid_params, as: :turbo_stream

            expect(response.body).to include('data-created="true"')
            area = Area.last
            decoded_body = CGI.unescapeHTML(response.body)
            expect(decoded_body).to include("\"id\":#{area.id}")
            expect(decoded_body).to include('"name":"Test Area"')
          end
        end

        context 'with invalid params' do
          let(:invalid_params) { { name: '', latitude: 52.52, longitude: 13.405, radius: 200 } }

          it 'does not create an area' do
            expect do
              post areas_url, params: invalid_params, as: :turbo_stream
            end.not_to change(Area, :count)
          end

          it 'returns turbo_stream flash error' do
            post areas_url, params: invalid_params, as: :turbo_stream

            expect_turbo_stream_response
            expect_flash_stream
          end
        end
      end
    end
  end
end
