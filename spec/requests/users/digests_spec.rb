# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/digests', type: :request do
  context 'when user is not signed in' do
    describe 'GET /index' do
      it 'redirects to the sign in page' do
        get users_digests_url

        expect(response.status).to eq(302)
      end
    end

    describe 'GET /show' do
      it 'redirects to the sign in page' do
        get users_digest_url(year: 2024)

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    describe 'POST /create' do
      it 'redirects to the sign in page' do
        post users_digests_url, params: { year: 2024 }

        expect(response.status).to eq(302)
      end
    end

    describe 'DELETE /destroy' do
      it 'redirects to the sign in page' do
        delete users_digest_url(year: 2024)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  context 'when user is signed in' do
    let(:user) { create(:user) }

    before { sign_in user }

    describe 'GET /index' do
      it 'renders a successful response' do
        get users_digests_url

        expect(response.status).to eq(200)
      end

      it 'displays existing digests' do
        digest = create(:users_digest, user:, year: 2024)

        get users_digests_url

        expect(response.body).to include('2024')
      end

      it 'shows empty state when no digests exist' do
        get users_digests_url

        expect(response.body).to include('No Year-End Digests Yet')
      end
    end

    describe 'GET /show' do
      let!(:digest) { create(:users_digest, user:, year: 2024) }

      it 'renders a successful response' do
        get users_digest_url(year: 2024)

        expect(response.status).to eq(200)
      end

      it 'includes digest content' do
        get users_digest_url(year: 2024)

        expect(response.body).to include('2024 Year in Review')
        expect(response.body).to include('Distance Traveled')
      end

      it 'redirects when digest not found' do
        get users_digest_url(year: 2020)

        expect(response).to redirect_to(users_digests_path)
        expect(flash[:alert]).to eq('Digest not found')
      end
    end

    describe 'POST /create' do
      context 'with valid year' do
        before do
          create(:stat, user:, year: 2024, month: 1)
        end

        it 'enqueues Users::Digests::CalculatingJob' do
          post users_digests_url, params: { year: 2024 }

          expect(Users::Digests::CalculatingJob).to have_been_enqueued.with(user.id, 2024)
        end

        it 'redirects with success notice' do
          post users_digests_url, params: { year: 2024 }

          expect(response).to redirect_to(users_digests_path)
          expect(flash[:notice]).to include('is being generated')
        end
      end

      context 'with invalid year' do
        it 'redirects with alert for year with no stats' do
          post users_digests_url, params: { year: 2024 }

          expect(response).to redirect_to(users_digests_path)
          expect(flash[:alert]).to eq('Invalid year selected')
        end

        it 'redirects with alert for year before 2000' do
          post users_digests_url, params: { year: 1999 }

          expect(response).to redirect_to(users_digests_path)
          expect(flash[:alert]).to eq('Invalid year selected')
        end

        it 'redirects with alert for future year' do
          post users_digests_url, params: { year: Time.current.year + 1 }

          expect(response).to redirect_to(users_digests_path)
          expect(flash[:alert]).to eq('Invalid year selected')
        end
      end

      context 'when user is inactive' do
        before do
          create(:stat, user:, year: 2024, month: 1)
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns an unauthorized response' do
          post users_digests_url, params: { year: 2024 }

          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq('Your account is not active.')
        end
      end
    end

    describe 'DELETE /destroy' do
      let!(:digest) { create(:users_digest, user:, year: 2024) }

      it 'deletes the digest' do
        expect do
          delete users_digest_url(year: 2024)
        end.to change(Users::Digest, :count).by(-1)
      end

      it 'redirects with success notice' do
        delete users_digest_url(year: 2024)

        expect(response).to redirect_to(users_digests_path)
        expect(flash[:notice]).to eq('Year-end digest for 2024 has been deleted')
      end

      it 'returns not found for non-existent digest' do
        delete users_digest_url(year: 2020)

        expect(response).to redirect_to(users_digests_path)
        expect(flash[:alert]).to eq('Digest not found')
      end

      it 'cannot delete another user digest' do
        other_user = create(:user)
        other_digest = create(:users_digest, user: other_user, year: 2023)

        delete users_digest_url(year: 2023)

        expect(response).to redirect_to(users_digests_path)
        expect(flash[:alert]).to eq('Digest not found')
        expect(other_digest.reload).to be_present
      end
    end
  end
end
