# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signup with pending import ticket' do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.com')
  end

  let!(:pending) { create(:pending_import, :with_file) }

  describe 'GET /users/sign_up?import_ticket=<uuid>' do
    it 'stashes the ticket in the session' do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      expect(session[:pending_import_ticket]).to eq(pending.claim_ticket)
    end

    it 'still renders the signup form' do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'reverse-trial signup (Cloud default variant)' do
    let(:signup_params) do
      {
        user: {
          email: "carryover-rt+#{SecureRandom.hex(4)}@example.com",
          password: 'safepassword',
          password_confirmation: 'safepassword'
        }
      }
    end

    before do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
    end

    it 'claims the import before redirecting to the manager checkout' do
      expect { post '/users', params: signup_params }
        .to change(Import, :count).by(1)

      expect(response).to redirect_to(%r{\Ahttps://manager\.example\.com/checkout})
      new_user = User.find_by(email: signup_params[:user][:email])
      expect(pending.reload.claimed_by_user_id).to eq(new_user.id)
    end
  end

  describe 'claim failure resilience' do
    let(:signup_params) do
      {
        user: {
          email: "carryover-err+#{SecureRandom.hex(4)}@example.com",
          password: 'safepassword',
          password_confirmation: 'safepassword'
        }
      }
    end

    before do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      allow(PendingImports::Claim).to receive(:new)
        .and_raise(ActiveRecord::RecordInvalid)
    end

    it 'still completes signup and warns instead of raising' do
      expect { post '/users', params: signup_params }
        .to change(User, :count).by(1)

      expect(flash[:alert]).to include("couldn't be queued")
    end
  end

  describe 'POST /users (signup completion)' do
    let(:signup_params) do
      {
        user: {
          email: "carryover+#{SecureRandom.hex(4)}@example.com",
          password: 'safepassword',
          password_confirmation: 'safepassword'
        }
      }
    end

    before do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
    end

    it 'claims the pending import after successful signup' do
      expect { post '/users', params: signup_params }
        .to change(Import, :count).by(1)
      new_user = User.find_by(email: signup_params[:user][:email])
      expect(new_user.imports.last.name).to eq(pending.original_filename)
    end

    it 'marks the pending_import as claimed' do
      post '/users', params: signup_params
      expect(pending.reload.claimed_at).not_to be_nil
      expect(pending.reload.claimed_by_user_id).to eq(User.last.id)
    end

    it 'sets a flash notice about the import' do
      post '/users', params: signup_params
      expect(flash[:notice]).to include(pending.original_filename)
    end

    it 'clears the ticket from the session after claim' do
      post '/users', params: signup_params
      expect(session[:pending_import_ticket]).to be_nil
    end
  end

  describe 'already-logged-in user visits /users/sign_up?import_ticket=X' do
    let(:existing_user) { create(:user) }

    before { sign_in existing_user }

    it 'claims the pending import immediately' do
      expect { get "/users/sign_up?import_ticket=#{pending.claim_ticket}" }
        .to change(existing_user.imports, :count).by(1)
    end

    it 'redirects to imports_path' do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      expect(response).to redirect_to(imports_path)
    end

    it 'sets a flash notice' do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      expect(flash[:notice]).to include(pending.original_filename)
    end

    it 'does NOT show an expired-ticket flash when ticket is valid' do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      expect(flash[:alert]).to be_blank
    end
  end

  describe 'expired ticket' do
    let!(:expired_pending) { create(:pending_import, :with_file, :expired) }
    let(:signup_params) do
      {
        user: {
          email: "expired+#{SecureRandom.hex(4)}@example.com",
          password: 'safepassword',
          password_confirmation: 'safepassword'
        }
      }
    end

    it 'shows an expired-ticket flash after signup' do
      get "/users/sign_up?import_ticket=#{expired_pending.claim_ticket}"
      post '/users', params: signup_params
      expect(flash[:alert]).to include('expired')
    end

    it 'does NOT create an Import' do
      get "/users/sign_up?import_ticket=#{expired_pending.claim_ticket}"
      expect { post '/users', params: signup_params }.not_to change(Import, :count)
    end
  end

  describe 'unknown ticket' do
    let(:signup_params) do
      {
        user: {
          email: "unknown+#{SecureRandom.hex(4)}@example.com",
          password: 'safepassword',
          password_confirmation: 'safepassword'
        }
      }
    end

    it 'shows an expired flash and creates no Import' do
      get '/users/sign_up?import_ticket=00000000-0000-0000-0000-000000000000'
      expect { post '/users', params: signup_params }.not_to change(Import, :count)
      expect(flash[:alert]).to include('expired')
    end
  end
end
