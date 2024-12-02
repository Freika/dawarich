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

  describe 'callbacks' do
    describe '#create_api_key' do
      let(:user) { create(:user) }

      it 'creates api key' do
        expect(user.api_key).to be_present
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
        expect(subject).to eq(%w[Germany France])
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
  end
end
