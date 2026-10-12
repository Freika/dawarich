# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/areas', type: :request do
  let(:user) { create(:user) }

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

          it 'returns turbo_stream with flash' do
            post areas_url, params: valid_params, as: :turbo_stream

            expect_turbo_stream_response
            expect_flash_stream('Area created successfully!')
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

  describe 'PATCH /update' do
    let(:area) { create(:area, user: user, name: 'Old Name', radius: 100) }
    let(:valid_params) { { name: 'New Name', latitude: 52.52, longitude: 13.405, radius: 250 } }

    context 'without authentication' do
      it 'redirects to login' do
        patch area_url(area), params: valid_params, as: :turbo_stream

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when signed in' do
      before { sign_in user }

      context 'with valid params' do
        it 'updates the area' do
          patch area_url(area), params: valid_params, as: :turbo_stream

          expect(area.reload.name).to eq('New Name')
          expect(area.radius).to eq(250)
        end

        it 'returns turbo_stream with flash' do
          patch area_url(area), params: valid_params, as: :turbo_stream

          expect_turbo_stream_response
          expect_flash_stream('Area updated successfully!')
        end
      end

      context 'with non-positive radius' do
        it 'does not update the area' do
          patch area_url(area), params: valid_params.merge(radius: 0), as: :turbo_stream

          expect(area.reload.radius).to eq(100)
        end

        it 'returns turbo_stream flash error' do
          patch area_url(area), params: valid_params.merge(radius: -5), as: :turbo_stream

          expect_turbo_stream_response
          expect_flash_stream
        end
      end

      context 'with out-of-range coordinates' do
        it 'rejects latitude above 90' do
          patch area_url(area), params: valid_params.merge(latitude: 91), as: :turbo_stream

          expect(area.reload.latitude.to_f).not_to eq(91)
          expect_flash_stream
        end

        it 'rejects longitude below -180' do
          patch area_url(area), params: valid_params.merge(longitude: -181), as: :turbo_stream

          expect(area.reload.longitude.to_f).not_to eq(-181)
          expect_flash_stream
        end
      end

      context "for another user's area" do
        let(:other_area) { create(:area, user: create(:user), name: 'Other') }

        it 'does not update it' do
          patch area_url(other_area), params: valid_params, as: :turbo_stream

          expect(other_area.reload.name).to eq('Other')
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end
