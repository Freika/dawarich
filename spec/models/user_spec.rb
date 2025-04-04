# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:imports).dependent(:destroy) }
    it { is_expected.to have_many(:points).through(:imports) }
    it { is_expected.to have_many(:stats) }
    it { is_expected.to have_many(:tracked_points).class_name('Point').dependent(:destroy) }
    it { is_expected.to have_many(:exports).dependent(:destroy) }
    it { is_expected.to have_many(:notifications).dependent(:destroy) }
    it { is_expected.to have_many(:areas).dependent(:destroy) }
    it { is_expected.to have_many(:visits).dependent(:destroy) }
    it { is_expected.to have_many(:places).through(:visits) }
    it { is_expected.to have_many(:trips).dependent(:destroy) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(inactive: 0, active: 1) }
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
        let!(:user) { create(:user, status: :inactive) }

        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        end

        it 'activates user after creation' do
          expect(user.active?).to be_truthy
        end
      end

      context 'when not self-hosted' do
        let!(:user) { create(:user, status: :inactive) }

        before do
          stub_const('SELF_HOSTED', false)
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        xit 'does not activate user' do
          expect(user.active?).to be_falsey
        end
      end
    end

    describe '#import_sample_points' do
      before do
        ENV['IMPORT_SAMPLE_POINTS'] = 'true'
      end

      after do
        ENV['IMPORT_SAMPLE_POINTS'] = nil
      end

      it 'creates a sample import and enqueues an import job' do
        user = create(:user)

        expect(user.imports.count).to eq(1)
        expect(user.imports.first.name).to eq('DELETE_ME_this_is_a_demo_import_DELETE_ME')
        expect(user.imports.first.source).to eq('gpx')

        expect(Import::ProcessJob).to have_been_enqueued.with(user.imports.first.id)
      end
    end
  end

  describe 'methods' do
    let(:user) { create(:user) }

    describe '#countries_visited' do
      subject { user.countries_visited }

      let!(:stat1) { create(:stat, user:, toponyms: [{ 'country' => 'Germany' }]) }
      let!(:stat2) { create(:stat, user:, toponyms: [{ 'country' => 'France' }]) }

      it 'returns array of countries' do
        expect(subject).to include('Germany', 'France')
        expect(subject.count).to eq(2)
      end
    end

    describe '#cities_visited' do
      subject { user.cities_visited }

      let!(:stat1) { create(:stat, user:, toponyms: [{ 'cities' => [{ 'city' => 'Berlin' }] }]) }
      let!(:stat2) { create(:stat, user:, toponyms: [{ 'cities' => [{ 'city' => 'Paris' }] }]) }

      it 'returns array of cities' do
        expect(subject).to eq(%w[Berlin Paris])
      end
    end

    describe '#total_distance' do
      subject { user.total_distance }

      let!(:stat1) { create(:stat, user:, distance: 10) }
      let!(:stat2) { create(:stat, user:, distance: 20) }

      it 'returns sum of distances' do
        expect(subject).to eq(30)
      end
    end

    describe '#total_countries' do
      subject { user.total_countries }

      let!(:stat) { create(:stat, user:, toponyms: [{ 'country' => 'Country' }]) }

      it 'returns number of countries' do
        expect(subject).to eq(1)
      end
    end

    describe '#total_cities' do
      subject { user.total_cities }

      let!(:stat) do
        create(
          :stat,
          user:,
          toponyms: [
            { 'cities' => [], 'country' => nil },
            { 'cities' => [{ 'city' => 'Berlin', 'points' => 64, 'timestamp' => 1_710_446_806, 'stayed_for' => 8772 }],
'country' => 'Germany' }
          ]
        )
      end

      it 'returns number of cities' do
        expect(subject).to eq(1)
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
          let(:user) { create(:user, status: :active) }

          it 'returns false' do
            expect(user.can_subscribe?).to be_falsey
          end
        end

        context 'when user is inactive' do
          let(:user) { create(:user, status: :inactive) }

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
          let(:user) { create(:user, status: :active) }

          it 'returns false' do
            expect(user.can_subscribe?).to be_falsey
          end
        end

        context 'when user is inactive' do
          let(:user) { create(:user, status: :inactive) }

          it 'returns true' do
            expect(user.can_subscribe?).to be_truthy
          end
        end
      end
    end
  end
end
