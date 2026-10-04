# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Registrations', type: :request do
  context 'A11 account security' do
    include ActiveSupport::Testing::TimeHelpers

    around do |example|
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    def account_client(user, remember: false)
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get('/users/sign_in')
      token = Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
      client.post('/users/sign_in', params: {
                    authenticity_token: token,
                    user: { email: user.email, password: 'a11rest-password-42', remember_me: remember ? '1' : '0' }
                  })
      expect(client.response.status).to eq(303)
      client.get('/users/edit')
      expect(client.response.status).to eq(200)
      client
    end

    def account_token(client)
      Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
    end

    def account_session(client)
      request = ActionDispatch::Request.new(Rails.application.env_config.dup)
      jar = ActionDispatch::Cookies::CookieJar.build(request,
                                                     '_dawarich_session' => client.cookies['_dawarich_session'])
      jar.encrypted['_dawarich_session']
    end

    def replace_account_session(client, data)
      jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
      jar.encrypted['_dawarich_session'] = { value: data }
      client.cookies['_dawarich_session'] = jar['_dawarich_session']
    end

    it 'matches the local credential update request matrix' do
      collision = create(:user, email: 'a11rest-taken@dawarich.test')
      deleted = create(:user, email: 'a11rest-deleted@dawarich.test')
      deleted.update_column(:deleted_at, Time.current)
      cases = [
        ['put', :put, {}, []], ['patch', :patch, {}, []],
        ['post_put', :post, { override: 'put' }, []], ['post_patch', :post, { override: 'patch' }, []],
        ['blank_current', :put, { current_password: '' }, ["Current password can't be blank"]],
        ['missing_current', :put, { omit_current: true }, ["Current password can't be blank"]],
        ['no_op_blank_current', :put, { same_email: true, current_password: '' }, ["Current password can't be blank"]],
        ['wrong_current', :put, { current_password: 'wrong-password' }, ['Current password is invalid']],
        ['email_only', :put, { email: ' A11REST-CHANGED@dawarich.test ' }, []],
        ['password_only', :put,
         { password: 'a11rest-new-password', password_confirmation: 'a11rest-new-password' }, []],
        ['both', :put, { email: 'a11rest-both@dawarich.test', password: 'a11rest-new-password',
                        password_confirmation: 'a11rest-new-password' }, []],
        ['no_op', :put, { same_email: true, password: '', password_confirmation: '' }, []],
        ['omitted_confirmation', :put, { password: 'a11rest-new-password' }, []],
        ['empty_confirmation', :put, { password: 'a11rest-new-password', password_confirmation: '' },
         ["Password confirmation doesn't match Password"]],
        ['mismatch_confirmation', :put, { password: 'a11rest-new-password', password_confirmation: 'different' },
         ["Password confirmation doesn't match Password"]],
        ['length_11', :put, { password: 'x' * 11 }, ['Password is too short (minimum is 12 characters)']],
        ['length_12', :put, { password: 'x' * 12 }, []], ['length_128', :put, { password: 'x' * 128 }, []],
        ['length_129', :put, { password: 'x' * 129 }, ['Password is too long (maximum is 128 characters)']],
        ['multibyte_11', :put, { password: 'ü' * 11 }, ['Password is too short (minimum is 12 characters)']],
        ['multibyte_12', :put, { password: 'ü' * 12 }, []],
        ['duplicate_email', :put, { email: collision.email.upcase }, ['Email has already been taken']],
        ['deleted_email', :put, { email: deleted.email }, ['Email has already been taken']],
        ['multiple_errors', :put,
         { email: '<bad>', password: 'short', password_confirmation: '', current_password: '' },
         ['Email is invalid', "Password confirmation doesn't match Password",
          'Password is too short (minimum is 12 characters)', "Current password can't be blank"]],
        ['blank_email', :put, { email: '' }, ["Email can't be blank"]],
        ['duplicate_scalar_email', :put, { duplicate_email: true }, []],
        ['duplicate_scalar_current', :put, { duplicate_current: true }, []],
        ['malformed_encoding', :put, { malformed: true }, nil],
        ['type_conflict', :put, { type_conflict: true }, nil]
      ]

      cases.each_with_index do |(name, method, options, errors), index|
        aggregate_failures(name) do
          user = create(:user, email: "a11rest-matrix-#{index}@dawarich.test", password: 'a11rest-password-42')
          client = account_client(user)
          before = user.reload.attributes
          params = { email: "a11rest-#{name}@dawarich.test", current_password: 'a11rest-password-42' }
          params.merge!(options.except(:override, :same_email, :duplicate_email, :duplicate_current,
                                       :malformed, :type_conflict, :omit_current))
          params.delete(:current_password) if options[:omit_current]
          params[:email] = user.email if options[:same_email] || name == 'password_only'
          body = URI.encode_www_form({ authenticity_token: account_token(client), _method: options[:override] }.compact)
          body += "&#{URI.encode_www_form(params.to_h { |key, value| ["user[#{key}]", value] })}"
          body += '&user%5Bemail%5D=a11rest-last%40dawarich.test' if options[:duplicate_email]
          body = "user%5Bcurrent_password%5D=wrong&#{body}" if options[:duplicate_current]
          body += '&user%5Bemail%5D=%FF' if options[:malformed]
          body += '&user%5Bemail%5D%5Bnested%5D=value' if options[:type_conflict]
          client.public_send(method, '/users', params: body,
                             headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' })
          expect(client.response.status).to eq(if errors.nil?
                                                 400
                                               else
                                                 errors.empty? ? 303 : 422
                                               end)
          after = user.reload.attributes
          if errors.nil? || errors.any?
            expect(after == before).to be(true)
            next if errors.nil?

            doc = Nokogiri::HTML5(client.response.body)
            expect(doc.css('#error_explanation li').map(&:text)).to eq(errors)
            expect(doc.at_css('#user_email')['value']).to eq(params[:email].strip.downcase)
            expect(doc.css('input[type="password"]').all? { |field| field['value'].blank? }).to be(true)
          else
            expect(client.response.location).to eq('http://www.example.com/')
            expected_email = options[:duplicate_email] ? 'a11rest-last@dawarich.test' : params[:email].strip.downcase
            expect(user.email).to eq(expected_email)
            password = params[:password].presence || 'a11rest-password-42'
            expect(user.valid_password?(password)).to be(true)
            expect(user.valid_password?('a11rest-password-42')).to be(params[:password].blank?)
            expect(after.except('email', 'encrypted_password', 'updated_at') ==
                   before.except('email', 'encrypted_password', 'updated_at')).to be(true)
            expect(after['updated_at'] == before['updated_at']).to be(name == 'no_op')
          end
        end
      end
    end

    it 'pins bypass session and recoverable effects without login callbacks' do
      %w[email_only password_only no_op key_rotation].each_with_index do |kind, index|
        aggregate_failures(kind) do
          user = create(:user, email: "a11rest-effects-#{index}@dawarich.test", password: 'a11rest-password-42')
          client = account_client(user, remember: true)
          user.update_columns(reset_password_token: "a11rest-reset-digest-#{index}", reset_password_sent_at: 1.hour.ago,
                              failed_attempts: 2, failed_otp_attempts: 3, otp_locked_at: 2.hours.ago)
          before = user.reload.attributes
          session = account_session(client).merge('devise.test' => 'expire', 'user_return_to' => '/stats',
                                                  'locale' => 'en', 'a11rest' => 'retain')
          replace_account_session(client, session)
          remember = client.cookies['remember_user_token']
          jobs = enqueued_jobs.size
          mails = ActionMailer::Base.deliveries.size
          if kind == 'key_rotation'
            client.post('/settings/generate_api_key', params: '',
                        headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
                                   'X-CSRF-Token' => account_token(client) })
          else
            params = { email: user.email, current_password: 'a11rest-password-42', password: '',
password_confirmation: '' }
            params[:email] = "a11rest-updated-#{index}@dawarich.test" if kind == 'email_only'
            if kind == 'password_only'
              params.merge!(password: 'a11rest-new-password', password_confirmation: 'a11rest-new-password')
            end
            client.put('/users', params: { user: params, authenticity_token: account_token(client) })
          end
          expect(client.response.status).to eq(kind == 'key_rotation' ? 302 : 303)
          after = user.reload.attributes
          received = account_session(client)
          expect(received.values_at('session_id', '_csrf_token', 'user_return_to', 'locale', 'a11rest') ==
                 session.values_at('session_id', '_csrf_token', 'user_return_to', 'locale', 'a11rest')).to be(true)
          expect(received.key?('devise.test')).to be(kind == 'key_rotation')
          expect(received.dig('warden.user.user.key',
                              1) == session.dig('warden.user.user.key', 1)).to be(kind != 'password_only')
          expect(received.dig('warden.user.user.key', 1) == user.authenticatable_salt).to be(true)
          expect(client.cookies['remember_user_token'] == remember).to be(true)
          unless kind == 'key_rotation'
            expect(received.dig('flash', 'flashes',
                                'notice')).to eq('Your account has been updated successfully.')
          end
          changed = %w[email_only password_only].include?(kind)
          expect(user.reset_password_token.nil?).to be(changed)
          expect(user.reset_password_sent_at.nil?).to be(changed)
          unless changed
            expect(after.values_at('reset_password_token', 'reset_password_sent_at') ==
                   before.values_at('reset_password_token', 'reset_password_sent_at')).to be(true)
          end
          ignored = %w[email encrypted_password updated_at api_key reset_password_token reset_password_sent_at]
          expect(after.except(*ignored) == before.except(*ignored)).to be(true)
          expect(after['updated_at'] == before['updated_at']).to be(kind == 'no_op')
          expect(enqueued_jobs.size).to eq(jobs)
          expect(ActionMailer::Base.deliveries.size).to eq(mails)
          old_client = ActionDispatch::Integration::Session.new(Rails.application)
          replace_account_session(old_client, session)
          old_client.get('/users/edit')
          expect(old_client.response.status).to eq(kind == 'password_only' ? 302 : 200)
          remembered_client = ActionDispatch::Integration::Session.new(Rails.application)
          remembered_client.cookies['remember_user_token'] = remember
          remembered_client.get('/users/edit')
          expect(remembered_client.response.status).to eq(kind == 'password_only' ? 302 : 200)
        end
      end
    end
  end

  let(:family_owner) { create(:user) }
  let(:family) { create(:family, creator: family_owner) }
  let!(:owner_membership) { create(:family_membership, user: family_owner, family: family, role: :owner) }
  let(:invitation) do
    create(:family_invitation, family: family, invited_by: family_owner, email: 'invited@example.com')
  end

  describe 'Family Invitation Registration Flow' do
    # Allow email/password registration for these tests
    before do
      stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
    end

    context 'when accessing registration with a valid invitation token' do
      it 'shows family-focused registration page' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Join #{family.name}!")
        expect(response.body).to include(family_owner.email)
        expect(response.body).to include(invitation.email)
        expect(response.body).to include('Create Account &amp; Join Family')
      end

      it 'renders the French invitation heading as one complete sentence' do
        get new_user_registration_path(invitation_token: invitation.token, locale: 'fr')

        expect(response.body).to include("Rejoindre #{family.name} !")
        expect(response.body).not_to include('Rejoindre.')
      end

      it 'pre-fills email field with invitation email' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response.body).to include('value="invited@example.com"')
      end

      it 'makes email field readonly' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response.body).to include('readonly')
      end

      it 'hides normal login links' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response.body).not_to include('devise/shared/links')
      end
    end

    context 'when accessing registration without invitation token' do
      it 'shows normal registration page' do
        get new_user_registration_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Almost there!')
        expect(response.body).to include('control over your location data')
        expect(response.body).not_to include('Join')
        expect(response.body).to include('Sign up')
      end
    end

    context 'when creating account with valid invitation token' do
      let(:user_params) do
        {
          email: invitation.email,
          password: 'password123456',
          password_confirmation: 'password123456'
        }
      end

      let(:request_params) do
        {
          user: user_params,
          invitation_token: invitation.token
        }
      end

      it 'creates user and accepts invitation automatically' do
        expect do
          post user_registration_path, params: request_params
        end.to change(User, :count).by(1)
                                   .and change { invitation.reload.status }.from('pending').to('accepted')

        new_user = User.find_by(email: invitation.email)
        expect(new_user).to be_present
        expect(new_user.family).to eq(family)
        expect(family.reload.members).to include(new_user)
      end

      it 'persists the chosen locale before creating the welcome notification' do
        post user_registration_path, params: request_params.merge(locale: 'fr')

        new_user = User.find_by!(email: invitation.email)
        expect(new_user.preferred_locale).to eq(:fr)
        expect(new_user.notifications.last.title).to eq('Bienvenue dans la famille !')
      end

      it 'redirects to family page after successful registration' do
        post user_registration_path, params: request_params

        expect(response).to redirect_to(family_path)
      end

      it 'displays success message with family name' do
        post user_registration_path, params: request_params

        # Check that user got the default registration success message
        # (family welcome message is set but may be overridden by Devise)
        expect(flash[:notice]).to include('signed up successfully')
      end
    end

    context 'when creating account with invalid invitation token' do
      it 'creates user but does not accept any invitation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'user@example.com',
              password: 'password123456',
              password_confirmation: 'password123456'
            },
            invitation_token: 'invalid-token'
          }
        end.to change(User, :count).by(1)

        new_user = User.find_by(email: 'user@example.com')
        expect(new_user.family).to be_nil
      end
    end

    context 'when invitation email does not match registration email' do
      it 'creates user but does not accept invitation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'different@example.com',
              password: 'password123456',
              password_confirmation: 'password123456'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        new_user = User.find_by(email: 'different@example.com')
        expect(new_user.family).to be_nil
        expect(invitation.reload.status).to eq('pending')
      end
    end
  end

  describe 'Self-Hosted Mode' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SELF_HOSTED').and_return('true')
    end

    context 'when accessing registration without invitation token and email/password registration disabled' do
      before do
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)
      end

      it 'redirects to root with error message' do
        get new_user_registration_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end

      it 'prevents account creation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'test@example.com',
              password: 'password123456',
              password_confirmation: 'password123456'
            }
          }
        end.not_to change(User, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end

      it 'rejects a user param that is not a hash without erroring' do
        expect do
          post user_registration_path, params: { user: 'test@example.com' }
        end.not_to change(User, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end
    end

    context 'when email/password registration is enabled' do
      before do
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
      end

      it 'allows registration page access' do
        get new_user_registration_path

        expect(response).to have_http_status(:success)
      end

      it 'allows account creation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'newuser@example.com',
              password: 'password123456',
              password_confirmation: 'password123456'
            }
          }
        end.to change(User, :count).by(1)

        user = User.find_by(email: 'newuser@example.com')
        expect(user).to be_present
        expect(response).to redirect_to(root_path)
      end
    end

    context 'when accessing registration with valid invitation token' do
      it 'allows registration page access' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Join #{family.name}!")
      end

      it 'allows account creation' do
        expect do
          post user_registration_path, params: {
            user: {
              email: invitation.email,
              password: 'password123456',
              password_confirmation: 'password123456'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        expect(response).to redirect_to(family_path)
      end

      it 'allows account creation when the email differs only in case' do
        expect do
          post user_registration_path, params: {
            user: {
              email: invitation.email.upcase,
              password: 'password123456',
              password_confirmation: 'password123456'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        expect(response).to redirect_to(family_path)
      end

      it 'prevents account creation for a different email' do
        expect do
          post user_registration_path, params: {
            user: {
              email: 'someone.else@example.com',
              password: 'password123456',
              password_confirmation: 'password123456'
            },
            invitation_token: invitation.token
          }
        end.not_to change(User, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('This invitation is not for your email address.')
        expect(invitation.reload.status).to eq('pending')
      end

      it 'renders the registration page when the user param is not a hash' do
        get new_user_registration_path(invitation_token: invitation.token, user: 'someone.else@example.com')

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when accessing registration with expired invitation' do
      before { invitation.update!(expires_at: 1.day.ago) }

      it 'redirects to root with error message' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end
    end

    context 'when accessing registration with cancelled invitation' do
      before { invitation.update!(status: :cancelled) }

      it 'redirects to root with error message' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end
    end
  end

  describe 'Non-Self-Hosted Mode' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    context 'when accessing registration without invitation token' do
      it 'allows normal registration' do
        get new_user_registration_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Almost there!')
      end

      it 'creates the account and redirects to Manager checkout (reverse_trial default)' do
        stub_const('MANAGER_URL', 'https://manager.example.com')
        unique_email = "newuser-#{Time.current.to_i}@example.com"

        expect do
          post user_registration_path, params: {
            user: {
              email: unique_email,
              password: 'password123456',
              password_confirmation: 'password123456'
            }
          }
        end.to change(User, :count).by(1)

        user = User.find_by(email: unique_email)
        expect(user).to be_present
        expect(user.signup_variant).to eq('reverse_trial')
        expect(response).to have_http_status(:redirect)
        expect(response.location).to start_with('https://manager.example.com/checkout')
      end
    end
  end

  describe 'Invitation Token Handling' do
    # Allow email/password registration for these tests
    before do
      stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
    end

    it 'accepts invitation token from params' do
      get new_user_registration_path(invitation_token: invitation.token)

      expect(response.body).to include("Join #{invitation.family.name}!")
    end

    it 'accepts invitation token from nested user params' do
      post user_registration_path, params: {
        user: {
          email: invitation.email,
          password: 'password123456',
          password_confirmation: 'password123456'
        },
        invitation_token: invitation.token
      }

      new_user = User.find_by(email: invitation.email)
      expect(new_user.family).to eq(family)
    end

    it 'handles session-stored invitation token' do
      # Simulate session storage by passing the token directly in params
      # (In real usage, this would come from the session after redirect from invitation page)
      get new_user_registration_path(invitation_token: invitation.token)

      expect(response.body).to include("Join #{invitation.family.name}!")
    end
  end

  describe 'Error Handling' do
    # Allow email/password registration for these tests
    before do
      stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
    end

    context 'when invitation acceptance fails' do
      before do
        # Mock service failure
        allow_any_instance_of(Families::AcceptInvitation).to receive(:call).and_return(false)
        allow_any_instance_of(Families::AcceptInvitation).to receive(:error_message).and_return('Mock error')
      end

      it 'creates user but shows invitation error in flash' do
        expect do
          post user_registration_path, params: {
            user: {
              email: invitation.email,
              password: 'password123456',
              password_confirmation: 'password123456'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        expect(flash[:alert]).to include('Mock error')
      end
    end

    context 'when invitation acceptance raises exception' do
      before do
        # Mock service exception
        allow_any_instance_of(Families::AcceptInvitation).to receive(:call).and_raise(StandardError, 'Test error')
      end

      it 'creates user but shows generic error in flash' do
        expect do
          post user_registration_path, params: {
            user: {
              email: invitation.email,
              password: 'password123456',
              password_confirmation: 'password123456'
            },
            invitation_token: invitation.token
          }
        end.to change(User, :count).by(1)

        expect(flash[:alert]).to include('there was an issue accepting the invitation')
      end
    end
  end

  describe 'Signup Intent Tracking' do
    context 'when self-hosted mode is disabled' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'shows signup intent dropdown on registration page' do
        get new_user_registration_path

        expect(response.body).to include('How do you plan to use Dawarich?')
        expect(response.body).to include('cloud')
        expect(response.body).to include('self_hosted_demo')
      end

      it 'does not show signup intent dropdown for family invitations' do
        get new_user_registration_path(invitation_token: invitation.token)

        expect(response.body).not_to include('How do you plan to use Dawarich?')
      end

      it 'stores cloud intent in user settings' do
        unique_email = "intent-cloud-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456',
            signup_intent: 'cloud'
          }
        }

        user = User.find_by(email: unique_email)
        expect(user.settings['signup_intent']).to eq('cloud')
      end

      it 'stores self_hosted_demo intent in user settings' do
        unique_email = "intent-demo-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456',
            signup_intent: 'self_hosted_demo'
          }
        }

        user = User.find_by(email: unique_email)
        expect(user.settings['signup_intent']).to eq('self_hosted_demo')
      end

      it 'ignores invalid intent values' do
        unique_email = "intent-invalid-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456',
            signup_intent: 'hacker'
          }
        }

        user = User.find_by(email: unique_email)
        expect(user.settings['signup_intent']).to be_nil
      end
    end

    context 'when self-hosted mode is enabled' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('SELF_HOSTED').and_return('true')
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
      end

      it 'does not show signup intent dropdown' do
        get new_user_registration_path

        expect(response.body).not_to include('How do you plan to use Dawarich?')
      end

      it 'does not store signup intent even if param is sent' do
        unique_email = "intent-selfhosted-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456',
            signup_intent: 'cloud'
          }
        }

        user = User.find_by(email: unique_email)
        expect(user.settings['signup_intent']).to be_nil
      end
    end
  end

  describe 'Validation Error Handling' do
    # Allow email/password registration for these tests
    before do
      stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
    end

    context 'when trying to register with an existing email' do
      let!(:existing_user) { create(:user, email: 'existing@example.com') }

      it 'renders the registration form with error message' do
        post user_registration_path, params: {
          user: {
            email: existing_user.email,
            password: 'password123456',
            password_confirmation: 'password123456'
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('Email has already been taken')
        expect(response.body).to include('error_explanation')
      end

      it 'does not create a new user' do
        expect do
          post user_registration_path, params: {
            user: {
              email: existing_user.email,
              password: 'password123456',
              password_confirmation: 'password123456'
            }
          }
        end.not_to change(User, :count)
      end
    end

    context 'when password is too short' do
      it 'renders the registration form with error message' do
        post user_registration_path, params: {
          user: {
            email: 'newuser@example.com',
            password: 'short',
            password_confirmation: 'short'
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('Password is too short')
        expect(response.body).to include('error_explanation')
      end
    end

    context 'when passwords do not match' do
      it 'renders the registration form with error message' do
        post user_registration_path, params: {
          user: {
            email: 'newuser@example.com',
            password: 'password123456',
            password_confirmation: 'different123'
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('Password confirmation doesn')
        expect(response.body).to include('error_explanation')
      end
    end
  end

  describe 'Account Deletion' do
    let(:user) { create(:user, password: 'password123456') }

    before do
      sign_in user
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    context 'cloud (non-self-hosted) — email-confirmation flow' do
      it 'does NOT delete immediately — sends a confirmation email instead' do
        expect do
          delete user_registration_path
        end.not_to(change(User, :count))

        expect(user.reload.deleted?).to be false
      end

      it 'enqueues the account-destroy confirmation email' do
        expect do
          delete user_registration_path
        end.to have_enqueued_job(Users::MailerSendingJob).with(
          user.id, 'account_destroy_confirmation', hash_including(:link_url)
        )
      end

      it 'does NOT enqueue Users::DestroyJob until the email is clicked' do
        expect do
          delete user_registration_path
        end.not_to have_enqueued_job(Users::DestroyJob)
      end

      it 'leaves the user signed in (they may want to cancel)' do
        delete user_registration_path

        expect(controller.current_user).to eq(user)
      end

      it 'redirects to settings with a confirmation-email message' do
        delete user_registration_path

        expect(response).to redirect_to(edit_user_registration_path)
        expect(flash[:notice]).to include('confirmation email')
      end

      it 'takes the email path without asking for a password or confirm_email' do
        expect do
          delete user_registration_path
        end.to have_enqueued_job(Users::MailerSendingJob)

        expect(flash[:alert]).to be_nil
      end

      it 'does not render the self-hosted confirmation fields on the account page' do
        get edit_user_registration_path

        expect(response.body).not_to include('name="confirm_email"')
        expect(response.body).to include('Email me the confirmation link')
      end

      it 'still warns that deletion is permanent' do
        get edit_user_registration_path

        expect(response.body).to include('This is permanent and removes all your data.')
      end
    end

    context 'self-hosted — password-confirmation flow' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'soft-deletes immediately when password is correct (no email)' do
        expect do
          delete user_registration_path, params: { password: 'password123456' }
        end.to have_enqueued_job(Users::DestroyJob).with(user.id)

        expect(user.reload.deleted_at).to be_present
      end

      it 'does NOT enqueue an email' do
        expect do
          delete user_registration_path, params: { password: 'password123456' }
        end.not_to have_enqueued_job(Users::MailerSendingJob)
      end

      it 'signs out the user after deletion' do
        delete user_registration_path, params: { password: 'password123456' }

        expect(controller.current_user).to be_nil
      end

      it 'rejects deletion without a password' do
        delete user_registration_path

        expect(response).to redirect_to(edit_user_registration_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.deleted_at).to be_nil
      end

      it 'rejects deletion with the wrong password' do
        delete user_registration_path, params: { password: 'wrong' }

        expect(response).to redirect_to(edit_user_registration_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.deleted_at).to be_nil
      end

      it 'logs a warning when confirmation fails' do
        allow(Rails.logger).to receive(:warn)

        delete user_registration_path, params: { password: 'wrong' }

        expect(Rails.logger).to have_received(:warn).with(/Account deletion confirmation failed/)
      end

      context 'when the user is an OIDC user (unknowable password)' do
        let(:oauth_user) do
          create(:user, provider: 'openid_connect', uid: 'oidc-123', password: SecureRandom.hex(16))
        end

        before { sign_in oauth_user }

        it 'soft-deletes when confirm_email matches (case-insensitive)' do
          expect do
            delete user_registration_path, params: { confirm_email: oauth_user.email.upcase }
          end.to have_enqueued_job(Users::DestroyJob).with(oauth_user.id)

          expect(oauth_user.reload.deleted_at).to be_present
        end

        it 'signs out and redirects after a confirmed deletion' do
          delete user_registration_path, params: { confirm_email: oauth_user.email }

          expect(controller.current_user).to be_nil
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to include('scheduled for deletion')
        end

        it 'tolerates surrounding whitespace in confirm_email' do
          expect do
            delete user_registration_path, params: { confirm_email: "  #{oauth_user.email.upcase}  " }
          end.to have_enqueued_job(Users::DestroyJob).with(oauth_user.id)

          expect(oauth_user.reload.deleted_at).to be_present
        end

        it 'rejects deletion when confirm_email is missing' do
          delete user_registration_path

          expect(response).to redirect_to(edit_user_registration_path)
          expect(flash[:alert]).to be_present
          expect(oauth_user.reload.deleted_at).to be_nil
        end

        it 'rejects deletion when confirm_email is wrong' do
          delete user_registration_path, params: { confirm_email: 'someone-else@example.com' }

          expect(response).to redirect_to(edit_user_registration_path)
          expect(flash[:alert]).to be_present
          expect(oauth_user.reload.deleted_at).to be_nil
        end

        it 'accepts a valid password from a linked user who knows one' do
          expect do
            delete user_registration_path, params: { password: oauth_user.password }
          end.to have_enqueued_job(Users::DestroyJob).with(oauth_user.id)

          expect(oauth_user.reload.deleted_at).to be_present
        end

        it 'rejects a wrong password when no confirm_email is given' do
          delete user_registration_path, params: { password: 'wrong' }

          expect(response).to redirect_to(edit_user_registration_path)
          expect(flash[:alert]).to be_present
          expect(oauth_user.reload.deleted_at).to be_nil
        end
      end
    end

    context 'when user is a family owner with members' do
      let(:user_family) { create(:family, creator: user) }
      let(:member) { create(:user) }

      before do
        create(:family_membership, user: user, family: user_family, role: :owner)
        create(:family_membership, user: member, family: user_family, role: :member)
      end

      it 'does not delete the account' do
        expect do
          delete user_registration_path
        end.not_to(change { user.reload.deleted_at })
      end

      it 'redirects back with an error message the browser can follow' do
        delete user_registration_path

        expect(response).to redirect_to(edit_user_registration_path)
        expect(response).to have_http_status(:found)
        expect(flash[:alert]).to eq('Cannot delete your account while you own a family with other members.')
      end

      it 'does not sign out the user' do
        delete user_registration_path

        expect(controller.current_user).to eq(user)
      end

      it 'does not enqueue deletion job' do
        expect do
          delete user_registration_path
        end.not_to have_enqueued_job(Users::DestroyJob)
      end

      it 'still refuses on self-hosted even when the password is correct' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

        expect do
          delete user_registration_path, params: { password: 'password123456' }
        end.not_to have_enqueued_job(Users::DestroyJob)

        expect(response).to redirect_to(edit_user_registration_path)
        expect(user.reload.deleted_at).to be_nil
      end
    end

    context 'concurrent deletion-request attempts' do
      it 'rate-limits to one confirmation email per user per window' do
        expect do
          delete user_registration_path
          delete user_registration_path
        end.to have_enqueued_job(Users::MailerSendingJob).once
      end

      it 'shows a flash alert on the throttled second request' do
        delete user_registration_path
        delete user_registration_path

        expect(flash[:alert]).to include('already sent')
      end
    end

    context 'when user can delete (family owner with no other members)' do
      let(:user_family) { create(:family, creator: user) }

      before do
        create(:family_membership, user: user, family: user_family, role: :owner)
      end

      it 'allows the deletion-request flow (cloud — email confirmation will perform the delete)' do
        expect do
          delete user_registration_path
        end.to have_enqueued_job(Users::MailerSendingJob).with(
          user.id, 'account_destroy_confirmation', hash_including(:link_url)
        )
      end
    end
  end

  describe 'UTM Parameter Tracking' do
    let(:utm_params) do
      {
        utm_source: 'google',
        utm_medium: 'cpc',
        utm_campaign: 'winter_2025',
        utm_term: 'location_tracking',
        utm_content: 'banner_ad'
      }
    end

    context 'when self-hosted mode is disabled' do
      # Off the self-hosted grant, joining a family is gated on the owner holding
      # the Family plan, so the fixture owner has to hold one for the invitation
      # path to be reachable at all.
      let(:family_owner) { create(:user, plan: :family, skip_auto_trial: true) }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'captures UTM parameters from registration page URL' do
        get new_user_registration_path, params: utm_params

        expect(response).to have_http_status(:ok)
        expect(session[:utm_source]).to eq('google')
        expect(session[:utm_medium]).to eq('cpc')
        expect(session[:utm_campaign]).to eq('winter_2025')
        expect(session[:utm_term]).to eq('location_tracking')
        expect(session[:utm_content]).to eq('banner_ad')
      end

      it 'stores UTM parameters in user record after registration' do
        # Visit registration page with UTM params
        get new_user_registration_path, params: utm_params

        # Create account
        unique_email = "utm-user-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456'
          }
        }

        # Verify UTM params were saved to user
        user = User.find_by(email: unique_email)
        expect(user.utm_source).to eq('google')
        expect(user.utm_medium).to eq('cpc')
        expect(user.utm_campaign).to eq('winter_2025')
        expect(user.utm_term).to eq('location_tracking')
        expect(user.utm_content).to eq('banner_ad')
      end

      it 'clears UTM parameters from session after registration' do
        # Visit registration page with UTM params
        get new_user_registration_path, params: utm_params

        # Create account
        unique_email = "utm-cleanup-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456'
          }
        }

        # Verify session was cleaned up
        expect(session[:utm_source]).to be_nil
        expect(session[:utm_medium]).to be_nil
        expect(session[:utm_campaign]).to be_nil
        expect(session[:utm_term]).to be_nil
        expect(session[:utm_content]).to be_nil
      end

      it 'handles partial UTM parameters' do
        partial_utm = { utm_source: 'twitter', utm_campaign: 'spring_promo' }

        get new_user_registration_path, params: partial_utm

        unique_email = "partial-utm-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456'
          }
        }

        user = User.find_by(email: unique_email)
        expect(user.utm_source).to eq('twitter')
        expect(user.utm_campaign).to eq('spring_promo')
        expect(user.utm_medium).to be_nil
        expect(user.utm_term).to be_nil
        expect(user.utm_content).to be_nil
      end

      it 'does not store empty UTM parameters' do
        empty_utm = {
          utm_source: '',
          utm_medium: '',
          utm_campaign: 'campaign_only'
        }

        get new_user_registration_path, params: empty_utm

        unique_email = "empty-utm-#{Time.current.to_i}@example.com"
        post user_registration_path, params: {
          user: {
            email: unique_email,
            password: 'password123456',
            password_confirmation: 'password123456'
          }
        }

        user = User.find_by(email: unique_email)
        expect(user.utm_source).to be_nil
        expect(user.utm_medium).to be_nil
        expect(user.utm_campaign).to eq('campaign_only')
      end

      it 'works with family invitations' do
        get new_user_registration_path, params: utm_params.merge(invitation_token: invitation.token)

        post user_registration_path, params: {
          user: {
            email: invitation.email,
            password: 'password123456',
            password_confirmation: 'password123456'
          },
          invitation_token: invitation.token
        }

        user = User.find_by(email: invitation.email)
        expect(user.utm_source).to eq('google')
        expect(user.utm_campaign).to eq('winter_2025')
        expect(user.family).to eq(family)
      end
    end

    context 'when self-hosted mode is enabled' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('SELF_HOSTED').and_return('true')
      end

      it 'does not capture UTM parameters' do
        # With valid invitation to allow registration in self-hosted mode
        get new_user_registration_path, params: utm_params.merge(invitation_token: invitation.token)

        expect(session[:utm_source]).to be_nil
        expect(session[:utm_medium]).to be_nil
        expect(session[:utm_campaign]).to be_nil
      end

      it 'does not store UTM parameters in user record' do
        # With valid invitation to allow registration in self-hosted mode
        get new_user_registration_path, params: utm_params.merge(invitation_token: invitation.token)

        post user_registration_path, params: {
          user: {
            email: invitation.email,
            password: 'password123456',
            password_confirmation: 'password123456'
          },
          invitation_token: invitation.token
        }

        user = User.find_by(email: invitation.email)
        expect(user.utm_source).to be_nil
        expect(user.utm_medium).to be_nil
        expect(user.utm_campaign).to be_nil
        expect(user.utm_term).to be_nil
        expect(user.utm_content).to be_nil
      end
    end
  end

  describe 'PUT /users (account update)' do
    context 'when an OAuth user sets a password' do
      let(:oauth_user) do
        create(:user, provider: 'google_oauth2', uid: '999', password: SecureRandom.hex(16))
      end

      before { sign_in oauth_user }

      it 'persists the new password so the user can sign in with email/password' do
        put user_registration_path, params: {
          user: {
            password: 'new-password-123',
            password_confirmation: 'new-password-123'
          }
        }

        expect(oauth_user.reload.valid_password?('new-password-123')).to be(true)
      end
    end

    context 'when an OAuth user updates profile fields without a password' do
      let(:oauth_user) do
        create(:user, provider: 'google_oauth2', uid: '998', password: 'original-secret-1')
      end

      before { sign_in oauth_user }

      it 'updates the profile and leaves the existing password intact' do
        put user_registration_path, params: {
          user: {
            email: oauth_user.email,
            password: '',
            password_confirmation: ''
          }
        }

        expect(oauth_user.reload.valid_password?('original-secret-1')).to be(true)
      end
    end
  end

  describe 'GET /users/edit (account settings)' do
    context 'when signed in as a Google OAuth user' do
      let(:oauth_user) { create(:user, provider: 'google_oauth2', uid: '777', password: SecureRandom.hex(16)) }

      # Providers stubbed so the shared partial would render the sign-in buttons
      # for an unguarded (signed-in) user; the buttons must be hidden instead.
      before do
        allow(User).to receive(:omniauth_providers).and_return([:google_oauth2])
        sign_in oauth_user
      end

      it 'renders without the "Sign in with Google" button' do
        get edit_user_registration_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('Sign in with Google')
      end

      it 'shows that the account is connected with Google' do
        get edit_user_registration_path

        expect(response.body).to include('Connected with Google')
      end
    end

    context 'when signed in as an Apple OAuth user' do
      let(:oauth_user) { create(:user, provider: 'apple', uid: '000.apple', password: SecureRandom.hex(16)) }

      before { sign_in oauth_user }

      it 'shows that the account is connected with Apple' do
        get edit_user_registration_path

        expect(response.body).to include('Connected with Apple')
      end
    end

    context 'when signed in as an email/password user' do
      let(:password_user) { create(:user, provider: nil, uid: nil) }

      before do
        allow(User).to receive(:omniauth_providers).and_return([:google_oauth2])
        sign_in password_user
      end

      it 'renders without an OAuth sign-in button or a connected indicator' do
        get edit_user_registration_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('Sign in with Google')
        expect(response.body).not_to include('Connected with')
      end
    end
  end
end
