# frozen_string_literal: true

require 'rails_helper'

# An invitee who opens the emailed link while signed out and then signs in must
# land in the family, whichever sign-in entry point they use.
RSpec.describe 'Signing in from a family invitation', type: :request do
  let(:owner) { create(:user, plan: :family) }
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }
  let(:invitee) { create(:user, email: 'invitee@example.com', password: 'password123456') }
  let!(:invitation) { create(:family_invitation, family: family, invited_by: owner, email: invitee.email) }

  def sign_in_with_password(user = invitee)
    post user_session_path, params: { user: { email: user.email, password: 'password123456' } }
  end

  it 'joins the family when signing in through the invitation page link' do
    get family_invitation_path(invitation.token)
    get new_user_session_path(invitation_token: invitation.token)
    sign_in_with_password

    expect(response).to redirect_to(family_path)
    expect(invitee.reload.family).to eq(family)
    expect(invitation.reload).to be_accepted
  end

  it 'joins the family when signing in through the generic login link' do
    get family_invitation_path(invitation.token)
    get new_user_session_path
    sign_in_with_password

    expect(response).to redirect_to(family_path)
    expect(invitee.reload.family).to eq(family)
  end

  it 'joins the family when the sign-in form posts its empty invitation field' do
    get family_invitation_path(invitation.token)
    get new_user_session_path
    post user_session_path, params: {
      invitation_token: '',
      user: { email: invitee.email, password: 'password123456' }
    }

    expect(response).to redirect_to(family_path)
    expect(invitee.reload.family).to eq(family)
  end

  it 'names the family it joined' do
    get family_invitation_path(invitation.token)
    sign_in_with_password

    expect(flash[:notice]).to include(family.name)
  end

  it 'keeps the other sign-in options on the sign-in page' do
    stub_const('APPLE_WEB_SIGN_IN_ENABLED', true)

    get family_invitation_path(invitation.token)
    get new_user_session_path

    expect(response.body).to include(apple_oauth_request_path)
  end

  it 'joins the family when signing up through the generic sign-up link' do
    stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
    newcomer_invitation = create(:family_invitation, family: family, invited_by: owner, email: 'newcomer@example.com')

    get family_invitation_path(newcomer_invitation.token)
    get new_user_registration_path
    post user_registration_path, params: {
      user: {
        email: 'newcomer@example.com', password: 'password123456',
        password_confirmation: 'password123456', invitation_token: ''
      }
    }

    expect(User.find_by(email: 'newcomer@example.com').family).to eq(family)
  end

  it 'does not reuse the accepted invitation on a later sign-in' do
    get family_invitation_path(invitation.token)
    sign_in_with_password
    delete destroy_user_session_path

    other = create(:user, password: 'password123456')
    sign_in_with_password(other)

    expect(response).to redirect_to(root_path)
  end

  it 'leaves the invitation pending and explains why when the email does not match' do
    stranger = create(:user, password: 'password123456')

    get family_invitation_path(invitation.token)
    sign_in_with_password(stranger)

    expect(response).to redirect_to(family_invitation_path(invitation.token))
    expect(flash[:alert]).to be_present
    expect(stranger.reload.family).to be_nil
    expect(invitation.reload).to be_pending
  end

  it 'does not join the family from a GET when already signed in' do
    sign_in invitee

    get new_user_session_path(invitation_token: invitation.token)

    expect(response).to redirect_to(family_invitation_path(invitation.token))
    expect(invitee.reload.family).to be_nil
    expect(invitation.reload).to be_pending
  end

  it 'joins the family after the two-factor step' do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    invitee.otp_secret = User.generate_otp_secret
    invitee.otp_required_for_login = true
    invitee.save!

    get family_invitation_path(invitation.token)
    sign_in_with_password
    post user_otp_challenge_path, params: { otp_attempt: invitee.current_otp }

    expect(response).to redirect_to(family_path)
    expect(invitee.reload.family).to eq(family)
    expect(flash[:notice]).to include(family.name)
  end

  describe 'Sign in with Apple' do
    let(:verifier_double) { instance_double(Auth::VerifyAppleToken) }

    before do
      stub_const('APPLE_WEB_SIGN_IN_ENABLED', true)
      stub_const('ENV', ENV.to_hash.merge(
                          'APPLE_WEB_SERVICES_ID' => 'app.dawarich.web',
                          'APPLE_WEB_TEAM_ID' => 'H000000B',
                          'APPLE_WEB_KEY_ID' => 'ABC123XYZ',
                          'APPLE_WEB_REDIRECT_URI' => 'https://dawarich.app/users/auth/apple/callback'
                        ))
      invitee.update!(provider: 'apple', uid: '000777.web.apple')
      allow(Auth::VerifyAppleToken).to receive(:new).and_return(verifier_double)
      allow(verifier_double).to receive(:call).and_return(
        sub: '000777.web.apple', email: invitee.email, email_verified: true, is_private_email: false
      )
      https!
    end

    it 'relays the invitation through the cross-site callback and joins the family' do
      get family_invitation_path(invitation.token)
      get '/users/auth/apple'
      state = Rack::Utils.parse_query(URI(response.headers['Location']).query)['state']

      # Apple's callback is a cross-site form POST, so the SameSite=Lax session
      # cookie does not come along.
      session_cookie_name = Rails.application.config.session_options[:key] ||
                            cookies.to_hash.keys.find { |k| k.include?('session') }
      expect(session_cookie_name).to be_present
      cookies.delete(session_cookie_name)

      post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: state }

      expect(response).to redirect_to(family_path)
      expect(invitee.reload.family).to eq(family)
      expect(cookies['apple_pending_invitation_token']).to be_blank
    end
  end
end
