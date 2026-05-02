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
    it {
      is_expected.to define_enum_for(:status)
        .with_values(inactive: 0, active: 1, trial: 2, pending_payment: 3)
    }
    it {
      is_expected.to define_enum_for(:subscription_source)
        .with_values(none: 0, paddle: 1, apple_iap: 2, google_play: 3)
        .with_prefix(:sub_source)
    }
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

    describe 'start_trial (invoked on create for cloud users)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        ActiveJob::Base.queue_adapter = :test
      end

      it 'sets trial status and active_until to 7 days from now' do
        user = create(:user, :inactive)

        expect(user.trial?).to be_truthy
        expect(user.active_until).to be_within(1.minute).of(7.days.from_now)
      end

      it 'leaves subscription_source as :none (legacy trial, no Paddle checkout yet)' do
        user = create(:user, :inactive)

        expect(user.subscription_source).to eq('none')
      end

      it 'enqueues trial webhook job' do
        expect { create(:user, :inactive) }.to have_enqueued_job(Users::TrialWebhookJob)
      end

      it 'enqueues the welcome email immediately' do
        expect { create(:user, :inactive) }
          .to have_enqueued_job(Users::MailerSendingJob).with(an_instance_of(Integer), 'welcome')
      end

      it 'enqueues the explore_features email with a 2-day delay' do
        expect { create(:user, :inactive) }
          .to have_enqueued_job(Users::MailerSendingJob).with(an_instance_of(Integer), 'explore_features')
      end

      it 'does not enqueue any billing-related emails (Manager service owns billing emails)' do
        user = create(:user, :inactive)

        %w[trial_expires_soon trial_expired post_trial_reminder_early post_trial_reminder_late
           trial_first_payment_soon trial_converted
           pending_payment_day_1 pending_payment_day_3 pending_payment_day_7].each do |billing_type|
          expect(Users::MailerSendingJob).not_to have_been_enqueued.with(user.id, billing_type)
        end
      end
    end

    describe '#invalidate_plan_rate_limit_cache' do
      let!(:user) do
        u = create(:user, skip_auto_trial: true)
        u.update_columns(plan: User.plans[:lite])
        u
      end
      let(:cache_key) { "rack_attack/plan/#{user.api_key}" }

      it 'evicts the rack_attack plan cache when plan changes' do
        Rails.cache.write(cache_key, 'lite', expires_in: 2.minutes)
        expect(Rails.cache.read(cache_key)).to eq('lite')

        user.update!(plan: :pro)

        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'does NOT evict the cache when an unrelated column changes' do
        Rails.cache.write(cache_key, 'lite', expires_in: 2.minutes)

        user.update!(active_until: 1.year.from_now)

        expect(Rails.cache.read(cache_key)).to eq('lite')
      end

      it 'evicts the cache using the previous api_key when api_key itself changes' do
        Rails.cache.write(cache_key, 'lite', expires_in: 2.minutes)

        user.update!(plan: :pro, api_key: 'rotated-key')

        expect(Rails.cache.read(cache_key)).to be_nil
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

    describe '#auto_converting_trial?' do
      # skip_auto_trial suppresses the after_commit `activate` (self-hosted)
      # and `start_trial` (cloud) hooks so the factory trait's values
      # (`status`, `active_until`) survive to the assertion instead of
      # being overwritten on commit.
      it 'is true for a Paddle reverse-trial user with a future active_until' do
        user = create(:user, :trial, skip_auto_trial: true, active_until: 1.week.from_now, subscription_source: :paddle)
        expect(user.auto_converting_trial?).to be true
      end

      it 'is true for an Apple IAP trial user' do
        user = create(:user, :trial, skip_auto_trial: true, active_until: 1.week.from_now,
subscription_source: :apple_iap)
        expect(user.auto_converting_trial?).to be true
      end

      it 'is true for a Google Play trial user' do
        user = create(:user, :trial, skip_auto_trial: true, active_until: 1.week.from_now,
subscription_source: :google_play)
        expect(user.auto_converting_trial?).to be true
      end

      it 'is false for a legacy trial user with no subscription source' do
        user = create(:user, :trial, skip_auto_trial: true, active_until: 1.week.from_now, subscription_source: :none)
        expect(user.auto_converting_trial?).to be false
      end

      it 'is false when the trial has expired (active_until in the past)' do
        user = create(:user, :trial, skip_auto_trial: true, active_until: 1.day.ago, subscription_source: :paddle)
        expect(user.auto_converting_trial?).to be false
      end

      it 'is false for an active (post-trial) user' do
        user = create(:user, :active, skip_auto_trial: true, active_until: 1.year.from_now,
subscription_source: :paddle)
        expect(user.auto_converting_trial?).to be false
      end

      it 'is false for a pending_payment user (no trial started yet)' do
        user = create(:user, skip_auto_trial: true, status: :pending_payment, active_until: nil,
subscription_source: :none)
        expect(user.auto_converting_trial?).to be false
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

    context 'when a local-password user exists with the same email' do
      let(:email) { 'existing@example.com' }
      let!(:existing_user) { create(:user, email: email, provider: nil, uid: nil) }

      it 'raises LinkVerificationSent rather than auto-linking' do
        expect { described_class.from_omniauth(auth_hash) }
          .to raise_error(Auth::FindOrCreateOauthUser::LinkVerificationSent)
      end

      it 'leaves the existing user unmodified' do
        described_class.from_omniauth(auth_hash)
      rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
        existing_user.reload
        expect(existing_user.provider).to be_nil
        expect(existing_user.uid).to be_nil
      end

      it 'does not create a new user' do
        expect do
          described_class.from_omniauth(auth_hash)
        rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
          nil
        end.not_to change(User, :count)
      end
    end

    context 'when an OAuth user already exists with this provider+uid' do
      let(:email) { 'linked@example.com' }
      let!(:existing_user) { create(:user, email: email, provider: 'github', uid: '123545') }

      it 'returns the linked user without creating a new one' do
        user = described_class.from_omniauth(auth_hash)
        expect(user).to eq(existing_user)
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
            },
            extra: {
              raw_info: { email_verified: true }
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

    context 'when email is blank or nil' do
      let(:email) { nil }

      it 'creates a user with a placeholder email so the account is reachable by uid' do
        user = described_class.from_omniauth(auth_hash)
        expect(user.persisted?).to be true
        expect(user.email).to include('@github.dawarich.app')
      end
    end
  end

  describe 'skip_auto_trial' do
    context 'on cloud (not self-hosted)' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'starts the trial by default (7-day trial window)' do
        user = create(:user, :inactive)
        expect(user.trial?).to be true
        expect(user.active_until).to be_within(1.minute).of(7.days.from_now)
      end

      it 'does not start the trial when skip_auto_trial is true' do
        user = create(:user, skip_auto_trial: true, status: :inactive, active_until: nil)
        expect(user.status).to eq('inactive')
        expect(user.active_until).to be_nil
      end
    end

    context 'on self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'auto-activates by default' do
        user = create(:user, :inactive)
        expect(user.active?).to be true
      end

      it 'does not auto-activate when skip_auto_trial is true' do
        user = create(:user, skip_auto_trial: true, status: :inactive, active_until: nil)
        expect(user.status).to eq('inactive')
        expect(user.active_until).to be_nil
      end
    end
  end

  describe '#generate_subscription_token' do
    let(:user) { create(:user) }
    let(:secret) { ENV.fetch('JWT_SECRET_KEY', 'test_secret') }

    def decode(token)
      JWT.decode(token, secret, true, { algorithm: 'HS256' }).first
    end

    it 'encodes user_id, email, and exp by default (no theme claim)' do
      payload = decode(user.generate_subscription_token)

      expect(payload['user_id']).to eq(user.id)
      expect(payload['email']).to eq(user.email)
      expect(payload).not_to have_key('theme')
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

    it "includes purpose: 'checkout' as a defense-in-depth audience claim" do
      payload = decode(user.generate_subscription_token)

      expect(payload['purpose']).to eq('checkout')
    end

    it 'includes a unique jti on every token' do
      payload_a = decode(user.generate_subscription_token)
      payload_b = decode(user.generate_subscription_token)

      expect(payload_a['jti']).to be_a(String)
      expect(payload_a['jti']).to be_present
      expect(payload_b['jti']).to be_a(String)
      expect(payload_a['jti']).not_to eq(payload_b['jti'])
    end

    it 'raises KeyError when JWT_SECRET_KEY is unset (fail-loud on misconfiguration)' do
      env_without_jwt = ENV.to_h.tap { |h| h.delete('JWT_SECRET_KEY') }
      stub_const('ENV', env_without_jwt)

      expect { user.generate_subscription_token }.to raise_error(KeyError)
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

    it 'does not index subscription_source (no query path filters by it)' do
      indexes = ActiveRecord::Base.connection.indexes(:users).map(&:columns)
      expect(indexes).not_to include(['subscription_source'])
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

    it 'exposes prefixed predicates (sub_source_paddle? etc.)' do
      user = create(:user, subscription_source: :paddle)
      expect(user.sub_source_paddle?).to be true
      expect(user.sub_source_none?).to be false
    end
  end

  describe 'email campaign scheduling on trial start' do
    include ActiveJob::TestHelper

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      ActiveJob::Base.queue_adapter = :test
    end

    after { clear_enqueued_jobs }

    it 'enqueues welcome and explore_features (product emails only; billing is owned by Manager)' do
      user = build(:user)
      user.save!

      expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'welcome')
      expect(Users::MailerSendingJob).to have_been_enqueued.with(user.id, 'explore_features')
    end

    it 'enqueues the trial webhook job so Manager can sync billing state' do
      user = build(:user)

      expect { user.save! }.to have_enqueued_job(Users::TrialWebhookJob).with(an_instance_of(Integer))
    end

    it 'does not enqueue any billing-related mailer jobs from start_trial' do
      user = build(:user)
      user.save!

      %w[trial_expires_soon trial_expired post_trial_reminder_early post_trial_reminder_late
         trial_first_payment_soon trial_converted
         pending_payment_day_1 pending_payment_day_3 pending_payment_day_7].each do |billing_type|
        expect(Users::MailerSendingJob).not_to have_been_enqueued.with(user.id, billing_type)
      end
    end
  end
end
