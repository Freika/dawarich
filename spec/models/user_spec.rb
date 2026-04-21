# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:imports).dependent(:destroy) }
    it { is_expected.to have_many(:stats) }
    it { is_expected.to have_many(:points).class_name('Point').dependent(:destroy) }
    it { is_expected.to have_many(:exports).dependent(:destroy) }
    it { is_expected.to have_many(:notifications).dependent(:destroy) }
    it { is_expected.to have_many(:areas).dependent(:destroy) }
    it { is_expected.to have_many(:visits).dependent(:destroy) }
    it { is_expected.to have_many(:places).dependent(:destroy) }
    it { is_expected.to have_many(:trips).dependent(:destroy) }
    it { is_expected.to have_many(:tracks).dependent(:destroy) }
    it { is_expected.to have_many(:tags).dependent(:destroy) }
    it { is_expected.to have_many(:visited_places).through(:visits) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(inactive: 0, active: 1, trial: 2, pending_payment: 3) }
    it { is_expected.to define_enum_for(:plan).with_values(lite: 0, pro: 1) }
  end

  describe 'callbacks' do
    describe '#create_api_key' do
      let(:user) { create(:user) }

      it 'creates api key' do
        expect(user.api_key).to be_present
      end
    end

    describe '#activate' do
      context 'when self-hosted' do
        let!(:user) { create(:user, :inactive) }

        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        end

        it 'activates user after creation' do
          expect(user.active?).to be_truthy
          expect(user.active_until).to be_within(1.minute).of(1000.years.from_now)
        end

        it 'sets plan to pro' do
          expect(user.pro?).to be true
        end
      end

      context 'when not self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        it 'sets user to trial instead of active' do
          user = create(:user, :inactive)

          expect(user.trial?).to be_truthy
          expect(user.active_until).to be_within(1.minute).of(7.days.from_now)
        end
      end
    end

    describe '#start_trial' do
      let(:user) { create(:user, :inactive) }

      it 'sets trial status and active_until to 7 days from now' do
        user.send(:start_trial)

        expect(user.reload.trial?).to be_truthy
        expect(user.active_until).to be_within(1.minute).of(7.days.from_now)
      end

      it 'leaves subscription_source as :none (legacy trial, no Paddle checkout yet)' do
        user.send(:start_trial)

        expect(user.reload.subscription_source).to eq('none')
      end

      it 'enqueues trial webhook job' do
        expect { user.send(:start_trial) }.to have_enqueued_job(Users::TrialWebhookJob).with(user.id)
      end

      it 'schedules product emails' do
        allow(user).to receive(:schedule_product_emails)

        user.send(:start_trial)

        expect(user).to have_received(:schedule_product_emails)
      end

      it 'schedules legacy trial emails' do
        allow(user).to receive(:schedule_legacy_trial_emails)

        user.send(:start_trial)

        expect(user).to have_received(:schedule_legacy_trial_emails)
      end

      it 'does not schedule paddle billing emails (user has not completed Paddle checkout)' do
        allow(user).to receive(:schedule_paddle_billing_emails)

        user.send(:start_trial)

        expect(user).not_to have_received(:schedule_paddle_billing_emails)
      end
    end

    describe '#schedule_product_emails' do
      let(:user) { create(:user, :inactive) }

      it 'schedules welcome email immediately' do
        expect { user.schedule_product_emails }
          .to have_enqueued_job(Users::MailerSendingJob).with(user.id, 'welcome')
      end

      it 'schedules explore_features email for day 2' do
        expect { user.schedule_product_emails }
          .to have_enqueued_job(Users::MailerSendingJob).with(user.id, 'explore_features')
      end
    end
  end

  describe 'methods' do
    let(:user) { create(:user) }

    describe '#oauth_user?' do
      it 'returns true when provider is set' do
        user.update_columns(provider: 'google_oauth2', uid: '12345')
        expect(user.oauth_user?).to be true
      end

      it 'returns false when provider is nil' do
        expect(user.oauth_user?).to be false
      end
    end

    describe '#trial_state?' do
      context 'when user has trial status and no tracked points' do
        let(:user) do
          user = build(:user, :trial)
          user.save!(validate: false)
          user.update_column(:status, 'trial')
          user
        end

        it 'returns true' do
          user.points.destroy_all

          expect(user.trial_state?).to be_truthy
        end
      end

      context 'when user has trial status but has tracked points' do
        let(:user) { create(:user, :trial) }

        before do
          create(:point, user: user)
        end

        it 'returns false' do
          expect(user.trial_state?).to be_falsey
        end
      end

      context 'when user is not on trial' do
        let(:user) { create(:user, :active) }

        it 'returns false' do
          expect(user.trial_state?).to be_falsey
        end
      end
    end

    describe '#countries_visited' do
      subject { user.countries_visited }

      let!(:stat) do
        create(:stat, user:, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin', 'stayed_for' => 120 }] },
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'stayed_for' => 90 }] },
                 { 'country' => 'Belgium', 'cities' => [] },
                 { 'country' => nil, 'cities' => [] },
                 { 'country' => '', 'cities' => [] }
               ])
      end

      it 'returns array of countries from stats toponyms' do
        expect(subject).to include('Germany', 'France')
        expect(subject.count).to eq(2)
      end

      it 'excludes nil and empty country names' do
        expect(subject).not_to include(nil, '')
      end

      it 'excludes drive-through countries with no qualifying cities' do
        expect(subject).not_to include('Belgium')
      end
    end

    describe '#cities_visited' do
      subject { user.cities_visited }

      let!(:stat) do
        create(:stat, user:, toponyms: [
                 { 'country' => 'Germany', 'cities' => [
                   { 'city' => 'Berlin', 'stayed_for' => 120 },
                   { 'city' => nil, 'stayed_for' => 60 },
                   { 'city' => '', 'stayed_for' => 60 }
                 ] },
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'stayed_for' => 90 }] }
               ])
      end

      it 'returns array of cities from stats toponyms' do
        expect(subject).to include('Berlin', 'Paris')
        expect(subject.count).to eq(2)
      end

      it 'excludes nil and empty city names' do
        expect(subject).not_to include(nil, '')
      end
    end

    describe '#total_distance' do
      subject { user.total_distance }

      let!(:stat1) { create(:stat, user:, year: 2020, month: 10, distance: 10_000) }
      let!(:stat2) { create(:stat, user:, year: 2020, month: 11, distance: 20_000) }

      it 'returns sum of distances' do
        expect(subject).to eq(30) # 30 km
      end
    end

    describe '#total_countries' do
      subject { user.total_countries }

      let!(:stat) do
        create(:stat, user:, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin', 'stayed_for' => 120 }] },
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'stayed_for' => 90 }] },
                 { 'country' => 'Belgium', 'cities' => [] },
                 { 'country' => nil, 'cities' => [] }
               ])
      end

      it 'returns number of countries with qualifying cities' do
        expect(subject).to eq(2)
      end

      it 'excludes drive-through countries with empty cities' do
        expect(user.countries_visited).not_to include('Belgium')
      end
    end

    describe '#total_cities' do
      subject { user.total_cities }

      let!(:stat) do
        create(:stat, user:, toponyms: [
                 { 'country' => 'Germany', 'cities' => [
                   { 'city' => 'Berlin', 'stayed_for' => 120 },
                   { 'city' => 'Paris', 'stayed_for' => 90 },
                   { 'city' => nil, 'stayed_for' => 60 }
                 ] }
               ])
      end

      it 'returns number of cities from stats toponyms' do
        expect(subject).to eq(2)
      end
    end

    describe '#total_reverse_geocoded_points' do
      subject { user.total_reverse_geocoded_points }

      let!(:reverse_geocoded_point) { create(:point, :reverse_geocoded, user:) }
      let!(:not_reverse_geocoded_point) { create(:point, user:, reverse_geocoded_at: nil) }

      it 'returns number of reverse geocoded points' do
        expect(subject).to eq(1)
      end
    end

    describe '#total_reverse_geocoded_points_without_data' do
      subject { user.total_reverse_geocoded_points_without_data }

      let!(:reverse_geocoded_point) { create(:point, :reverse_geocoded, :with_geodata, user:) }
      let!(:reverse_geocoded_point_without_data) { create(:point, :reverse_geocoded, user:, geodata: {}) }

      it 'returns number of reverse geocoded points without data' do
        expect(subject).to eq(1)
      end
    end

    describe '#years_tracked' do
      let!(:points) do
        (1..3).map do |i|
          create(:point, user:, timestamp: DateTime.new(2024, 1, 1, 5, 0, 0) + i.minutes)
        end
      end

      it 'returns years tracked' do
        expect(user.years_tracked).to eq([{ year: 2024, months: ['Jan'] }])
      end
    end

    describe '#can_subscribe?' do
      context 'when Dawarich is self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        end

        context 'when user is active' do
          let!(:user) { create(:user, status: :active, active_until: 1000.years.from_now) }

          it 'returns false' do
            expect(user.can_subscribe?).to be_falsey
          end
        end

        context 'when user is inactive' do
          let(:user) { create(:user, :inactive) }

          it 'returns false' do
            expect(user.can_subscribe?).to be_falsey
          end
        end
      end

      context 'when Dawarich is not self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        context 'when user is active' do
          let(:user) { create(:user, status: :active, active_until: 1000.years.from_now) }

          it 'returns false' do
            user.update(status: :active)

            expect(user.can_subscribe?).to be_falsey
          end
        end

        context 'when user is inactive' do
          let(:user) do
            user = build(:user, :inactive)
            user.save!(validate: false)
            user.update_columns(status: 'inactive', active_until: 1.day.ago)
            user
          end

          it 'returns true' do
            expect(user.can_subscribe?).to be_truthy
          end
        end

        context 'when user is on trial' do
          let(:user) { create(:user, :trial, active_until: 1.week.from_now) }

          it 'returns true' do
            expect(user.can_subscribe?).to be_truthy
          end
        end
      end
    end

    describe '#export_data' do
      it 'enqueues the export data job' do
        expect { user.export_data }.to have_enqueued_job(Users::ExportDataJob).with(user.id)
      end
    end

    describe '#timezone' do
      context 'when timezone is not set in settings' do
        it 'returns UTC as default' do
          expect(user.timezone).to eq('UTC')
        end
      end

      context 'when timezone is set in settings' do
        let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

        it 'returns the user timezone from settings' do
          expect(user.timezone).to eq('Europe/Berlin')
        end
      end

      context 'when timezone is set to America/New_York' do
        let(:user) { create(:user, settings: { 'timezone' => 'America/New_York' }) }

        it 'returns the configured timezone' do
          expect(user.timezone).to eq('America/New_York')
        end
      end
    end
  end

  describe '.from_omniauth' do
    let(:auth_hash) do
      OmniAuth::AuthHash.new(
        {
          provider: 'github',
          uid: '123545',
          info: {
            email: email,
            name: 'Test User'
          }
        }
      )
    end

    context 'when user exists with the same email' do
      let(:email) { 'existing@example.com' }
      let!(:existing_user) { create(:user, email: email) }

      it 'returns the existing user' do
        user = described_class.from_omniauth(auth_hash)
        expect(user).to eq(existing_user)
        expect(user.persisted?).to be true
      end

      it 'does not create a new user' do
        expect do
          described_class.from_omniauth(auth_hash)
        end.not_to change(User, :count)
      end
    end

    context 'when user exists with different email casing' do
      let(:email) { 'Existing@Example.COM' }
      let!(:existing_user) { create(:user, email: 'existing@example.com') }

      it 'finds the existing user regardless of case' do
        user = described_class.from_omniauth(auth_hash)
        expect(user).to eq(existing_user)
        expect(user.persisted?).to be true
      end

      it 'does not create a new user' do
        expect do
          described_class.from_omniauth(auth_hash)
        end.not_to change(User, :count)
      end
    end

    context 'when user does not exist' do
      let(:email) { 'new@example.com' }

      it 'creates a new user with the OAuth email' do
        expect do
          described_class.from_omniauth(auth_hash)
        end.to change(User, :count).by(1)

        user = User.last
        expect(user.email).to eq(email)
      end

      it 'generates a random password for the new user' do
        user = described_class.from_omniauth(auth_hash)
        expect(user.encrypted_password).to be_present
      end

      it 'returns a persisted user' do
        user = described_class.from_omniauth(auth_hash)
        expect(user.persisted?).to be true
      end
    end

    context 'when OAuth provider is Google' do
      let(:email) { 'google@example.com' }
      let(:auth_hash) do
        OmniAuth::AuthHash.new(
          {
            provider: 'google_oauth2',
            uid: '123545',
            info: {
              email: email,
              name: 'Google User'
            }
          }
        )
      end

      it 'creates a user from Google OAuth data' do
        user = described_class.from_omniauth(auth_hash)
        expect(user.email).to eq(email)
        expect(user.persisted?).to be true
      end
    end

    context 'when email is nil' do
      let(:email) { nil }

      it 'attempts to create a user but fails validation' do
        user = described_class.from_omniauth(auth_hash)
        expect(user.persisted?).to be false
        expect(user.errors[:email]).to be_present
      end
    end

    context 'when email is blank' do
      let(:email) { '' }

      it 'attempts to create a user but fails validation' do
        user = described_class.from_omniauth(auth_hash)
        expect(user.persisted?).to be false
        expect(user.errors[:email]).to be_present
      end
    end
  end

  describe '#generate_subscription_token' do
    let(:user) { create(:user) }
    let(:secret) { ENV.fetch('JWT_SECRET_KEY', 'test_secret') }

    def decode(token)
      JWT.decode(token, secret, true, { algorithm: 'HS256' }).first
    end

    it 'encodes user_id, email, theme, and exp by default' do
      payload = decode(user.generate_subscription_token)

      expect(payload['user_id']).to eq(user.id)
      expect(payload['email']).to eq(user.email)
      expect(payload).to have_key('theme')
      expect(payload['exp']).to be > Time.current.to_i
      expect(payload).not_to have_key('plan')
      expect(payload).not_to have_key('interval')
    end

    it 'includes plan and interval when provided' do
      payload = decode(user.generate_subscription_token(plan: 'pro', interval: 'annual'))

      expect(payload['plan']).to eq('pro')
      expect(payload['interval']).to eq('annual')
    end

    it 'omits plan/interval when blank' do
      payload = decode(user.generate_subscription_token(plan: '', interval: nil))

      expect(payload).not_to have_key('plan')
      expect(payload).not_to have_key('interval')
    end
  end

  describe 'subscription columns' do
    it 'has a subscription_source column defaulting to 0' do
      user = create(:user)
      expect(user.read_attribute_before_type_cast(:subscription_source)).to eq(0)
    end

    it 'has a nullable signup_variant column' do
      user = create(:user)
      expect(user.signup_variant).to be_nil
    end

    it 'indexes subscription_source for query performance' do
      indexes = ActiveRecord::Base.connection.indexes(:users).map(&:columns)
      expect(indexes).to include(['subscription_source'])
    end
  end

  describe 'status enum' do
    it 'includes pending_payment with value 3' do
      expect(User.statuses['pending_payment']).to eq(3)
    end

    it 'exposes predicate pending_payment?' do
      user = create(:user)
      user.update!(status: :pending_payment)
      expect(user.pending_payment?).to be true
    end
  end

  describe 'subscription_source enum' do
    it 'defaults to :none for new users' do
      user = create(:user)
      expect(user.subscription_source).to eq('none')
    end

    it 'accepts paddle, apple_iap, google_play' do
      user = create(:user)
      %i[paddle apple_iap google_play].each do |source|
        user.update!(subscription_source: source)
        expect(user.subscription_source).to eq(source.to_s)
      end
    end
  end

  describe 'skip_auto_trial' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    it 'does not call start_trial when skip_auto_trial is true' do
      user = build(:user, skip_auto_trial: true)
      expect(user).not_to receive(:start_trial)
      user.save!
    end

    it 'still calls start_trial by default' do
      user = build(:user)
      expect(user).to receive(:start_trial).and_call_original
      user.save!
    end

    it 'leaves a skip_auto_trial user in inactive status (no trial granted)' do
      user = create(:user, skip_auto_trial: true, status: :inactive, active_until: nil)
      expect(user.status).to eq('inactive')
      expect(user.active_until).to be_nil
    end
  end

  describe 'email campaign scheduling' do
    include ActiveJob::TestHelper

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      ActiveJob::Base.queue_adapter = :test
    end

    after { clear_enqueued_jobs }

    it 'schedules product emails for a paddle-sourced trial user' do
      user = create(:user, subscription_source: :paddle, skip_auto_trial: true)
      clear_enqueued_jobs
      user.schedule_product_emails
      expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'welcome')
      expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'explore_features')
    end

    it 'schedules paddle billing emails only for paddle-sourced users' do
      paddle_user = create(:user, subscription_source: :paddle, skip_auto_trial: true)
      iap_user = create(:user, subscription_source: :apple_iap, skip_auto_trial: true)
      clear_enqueued_jobs

      paddle_user.schedule_paddle_billing_emails
      iap_user.schedule_paddle_billing_emails

      expect(Users::MailerSendingJob).to have_been_enqueued.with(paddle_user.id, 'trial_first_payment_soon')
      expect(Users::MailerSendingJob).not_to have_been_enqueued.with(iap_user.id, 'trial_first_payment_soon')
    end

    describe '#schedule_legacy_trial_emails' do
      let(:user) { create(:user, skip_auto_trial: true) }

      before { clear_enqueued_jobs }

      it 'schedules trial_expires_soon for day 5' do
        user.schedule_legacy_trial_emails

        expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'trial_expires_soon')
      end

      it 'schedules trial_expired for day 7' do
        user.schedule_legacy_trial_emails

        expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'trial_expired')
      end

      it 'schedules post_trial_reminder_early for day 9' do
        user.schedule_legacy_trial_emails

        expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'post_trial_reminder_early')
      end

      it 'schedules post_trial_reminder_late for day 14' do
        user.schedule_legacy_trial_emails

        expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'post_trial_reminder_late')
      end

      it 'schedules all four emails' do
        expect { user.schedule_legacy_trial_emails }
          .to have_enqueued_job(Users::MailerSendingJob).exactly(4).times
      end
    end

    it 'start_trial schedules product + legacy trial emails for legacy cloud signups' do
      user = build(:user)
      expect(user).to receive(:schedule_product_emails).and_call_original
      expect(user).to receive(:schedule_legacy_trial_emails).and_call_original
      expect(user).not_to receive(:schedule_paddle_billing_emails)
      user.save!
    end

    it 'start_trial actually enqueues legacy trial emails (not paddle-specific emails)' do
      user = build(:user)
      user.save!

      expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'trial_expires_soon')
      expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'trial_expired')
      expect(Users::MailerSendingJob).not_to have_been_enqueued.with(user.id, 'trial_first_payment_soon')
      expect(Users::MailerSendingJob).not_to have_been_enqueued.with(user.id, 'trial_converted')
    end
  end
end
