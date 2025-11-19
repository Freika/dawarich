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
    it { is_expected.to have_many(:places).through(:visits) }
    it { is_expected.to have_many(:trips).dependent(:destroy) }
    it { is_expected.to have_many(:tracks).dependent(:destroy) }
    it { is_expected.to have_many(:tags).dependent(:destroy) }
    it { is_expected.to have_many(:visited_places).through(:visits) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(inactive: 0, active: 1, trial: 2) }
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

      before do
        allow(Users::TrialWebhookJob).to receive(:perform_later)
      end

      it 'sets trial status and active_until to 7 days from now' do
        user.send(:start_trial)

        expect(user.reload.trial?).to be_truthy
        expect(user.active_until).to be_within(1.minute).of(7.days.from_now)
      end

      it 'enqueues trial webhook job' do
        expect(Users::TrialWebhookJob).to receive(:perform_later).with(user.id)
        user.send(:start_trial)
      end

      it 'schedules welcome emails' do
        allow(user).to receive(:schedule_welcome_emails)

        user.send(:start_trial)

        expect(user).to have_received(:schedule_welcome_emails)
      end
    end

    describe '#schedule_welcome_emails' do
      let(:user) { create(:user, :inactive) }

      before do
        allow(Users::MailerSendingJob).to receive(:perform_later)
        allow(Users::MailerSendingJob).to receive(:set).and_return(Users::MailerSendingJob)
      end

      it 'schedules welcome email immediately' do
        expect(Users::MailerSendingJob).to receive(:perform_later).with(user.id, 'welcome')
        user.send(:schedule_welcome_emails)
      end

      it 'schedules explore_features email for day 2' do
        expect(Users::MailerSendingJob).to receive(:set).with(wait: 2.days).and_return(Users::MailerSendingJob)
        expect(Users::MailerSendingJob).to receive(:perform_later).with(user.id, 'explore_features')
        user.send(:schedule_welcome_emails)
      end

      it 'schedules trial_expires_soon email for day 5' do
        expect(Users::MailerSendingJob).to receive(:set).with(wait: 5.days).and_return(Users::MailerSendingJob)
        expect(Users::MailerSendingJob).to receive(:perform_later).with(user.id, 'trial_expires_soon')
        user.send(:schedule_welcome_emails)
      end

      it 'schedules trial_expired email for day 7' do
        expect(Users::MailerSendingJob).to receive(:set).with(wait: 7.days).and_return(Users::MailerSendingJob)
        expect(Users::MailerSendingJob).to receive(:perform_later).with(user.id, 'trial_expired')
        user.send(:schedule_welcome_emails)
      end
    end
  end

  describe 'methods' do
    let(:user) { create(:user) }

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

      let!(:point1) { create(:point, user:, country_name: 'Germany') }
      let!(:point2) { create(:point, user:, country_name: 'France') }
      let!(:point3) { create(:point, user:, country_name: nil) }
      let!(:point4) { create(:point, user:, country_name: '') }

      it 'returns array of countries' do
        expect(subject).to include('Germany', 'France')
        expect(subject.count).to eq(2)
      end

      it 'excludes nil and empty country names' do
        expect(subject).not_to include(nil, '')
      end
    end

    describe '#cities_visited' do
      subject { user.cities_visited }

      let!(:point1) { create(:point, user:, city: 'Berlin') }
      let!(:point2) { create(:point, user:, city: 'Paris') }
      let!(:point3) { create(:point, user:, city: nil) }
      let!(:point4) { create(:point, user:, city: '') }

      it 'returns array of cities' do
        expect(subject).to include('Berlin', 'Paris')
        expect(subject.count).to eq(2)
      end

      it 'excludes nil and empty city names' do
        expect(subject).not_to include(nil, '')
      end
    end

    describe '#total_distance' do
      subject { user.total_distance }

      let!(:stat1) { create(:stat, user:, distance: 10_000) }
      let!(:stat2) { create(:stat, user:, distance: 20_000) }

      it 'returns sum of distances' do
        expect(subject).to eq(30) # 30 km
      end
    end

    describe '#total_countries' do
      subject { user.total_countries }

      let!(:point1) { create(:point, user:, country_name: 'Germany') }
      let!(:point2) { create(:point, user:, country_name: 'France') }
      let!(:point3) { create(:point, user:, country_name: nil) }

      it 'returns number of countries' do
        expect(subject).to eq(2)
      end
    end

    describe '#total_cities' do
      subject { user.total_cities }

      let!(:point1) { create(:point, user:, city: 'Berlin') }
      let!(:point2) { create(:point, user:, city: 'Paris') }
      let!(:point3) { create(:point, user:, city: nil) }

      it 'returns number of cities' do
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
      it 'returns the app timezone' do
        expect(user.timezone).to eq(Time.zone.name)
      end
    end
  end

  describe '.from_omniauth' do
    let(:auth_hash) do
      OmniAuth::AuthHash.new({
        provider: 'github',
        uid: '123545',
        info: {
          email: email,
          name: 'Test User'
        }
      })
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
        OmniAuth::AuthHash.new({
          provider: 'google_oauth2',
          uid: '123545',
          info: {
            email: email,
            name: 'Google User'
          }
        })
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
end
