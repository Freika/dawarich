# frozen_string_literal: true

require 'rails_helper'

RSpec.describe YearlyDigest, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:year) }
    it { is_expected.to validate_presence_of(:period_type) }

    describe 'uniqueness of year within scope' do
      let(:user) { create(:user) }
      let!(:existing_digest) { create(:yearly_digest, user: user, year: 2024, period_type: :yearly) }

      it 'does not allow duplicate yearly digest for same user and year' do
        duplicate = build(:yearly_digest, user: user, year: 2024, period_type: :yearly)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:year]).to include('has already been taken')
      end

      it 'allows same year for different period types' do
        monthly = build(:yearly_digest, user: user, year: 2024, period_type: :monthly)
        expect(monthly).to be_valid
      end

      it 'allows same year for different users' do
        other_user = create(:user)
        other_digest = build(:yearly_digest, user: other_user, year: 2024, period_type: :yearly)
        expect(other_digest).to be_valid
      end
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:period_type).with_values(monthly: 0, yearly: 1) }
  end

  describe 'callbacks' do
    describe 'before_create :generate_sharing_uuid' do
      it 'generates a sharing_uuid if not present' do
        digest = build(:yearly_digest, sharing_uuid: nil)
        digest.save!
        expect(digest.sharing_uuid).to be_present
      end

      it 'does not overwrite existing sharing_uuid' do
        existing_uuid = SecureRandom.uuid
        digest = build(:yearly_digest, sharing_uuid: existing_uuid)
        digest.save!
        expect(digest.sharing_uuid).to eq(existing_uuid)
      end
    end
  end

  describe 'helper methods' do
    let(:user) { create(:user) }
    let(:digest) { create(:yearly_digest, user: user) }

    describe '#countries_count' do
      it 'returns count of countries from toponyms' do
        expect(digest.countries_count).to eq(3)
      end

      context 'when toponyms countries is nil' do
        before { digest.update(toponyms: {}) }

        it 'returns 0' do
          expect(digest.countries_count).to eq(0)
        end
      end
    end

    describe '#cities_count' do
      it 'returns count of cities from toponyms' do
        expect(digest.cities_count).to eq(5) # Berlin, Munich, Paris, Madrid, Barcelona
      end

      context 'when toponyms cities is nil' do
        before { digest.update(toponyms: {}) }

        it 'returns 0' do
          expect(digest.cities_count).to eq(0)
        end
      end
    end

    describe '#first_time_countries' do
      it 'returns first time countries' do
        expect(digest.first_time_countries).to eq(['Spain'])
      end

      context 'when first_time_visits countries is nil' do
        before { digest.update(first_time_visits: {}) }

        it 'returns empty array' do
          expect(digest.first_time_countries).to eq([])
        end
      end
    end

    describe '#first_time_cities' do
      it 'returns first time cities' do
        expect(digest.first_time_cities).to eq(%w[Madrid Barcelona])
      end

      context 'when first_time_visits cities is nil' do
        before { digest.update(first_time_visits: {}) }

        it 'returns empty array' do
          expect(digest.first_time_cities).to eq([])
        end
      end
    end

    describe '#top_countries_by_time' do
      it 'returns countries sorted by time spent' do
        expect(digest.top_countries_by_time.first['name']).to eq('Germany')
      end
    end

    describe '#top_cities_by_time' do
      it 'returns cities sorted by time spent' do
        expect(digest.top_cities_by_time.first['name']).to eq('Berlin')
      end
    end

    describe '#yoy_distance_change' do
      it 'returns year over year distance change percent' do
        expect(digest.yoy_distance_change).to eq(15)
      end

      context 'when no previous year data' do
        let(:digest) { create(:yearly_digest, :without_previous_year, user: user) }

        it 'returns nil' do
          expect(digest.yoy_distance_change).to be_nil
        end
      end
    end

    describe '#previous_year' do
      it 'returns previous year' do
        expect(digest.previous_year).to eq(2023)
      end
    end

    describe '#total_countries_all_time' do
      it 'returns all time countries count' do
        expect(digest.total_countries_all_time).to eq(10)
      end
    end

    describe '#total_cities_all_time' do
      it 'returns all time cities count' do
        expect(digest.total_cities_all_time).to eq(45)
      end
    end

    describe '#total_distance_all_time' do
      it 'returns all time distance' do
        expect(digest.total_distance_all_time).to eq(2_500_000)
      end
    end

    describe '#distance_km' do
      it 'converts distance from meters to km' do
        expect(digest.distance_km).to eq(500.0)
      end
    end

    describe '#distance_comparison_text' do
      context 'when distance is less than Earth circumference' do
        it 'returns Earth circumference comparison' do
          expect(digest.distance_comparison_text).to include("Earth's circumference")
        end
      end

      context 'when distance is more than Moon distance' do
        before { digest.update(distance: 500_000_000) } # 500k km

        it 'returns Moon distance comparison' do
          expect(digest.distance_comparison_text).to include('Moon')
        end
      end
    end
  end

  describe 'sharing settings' do
    let(:user) { create(:user) }
    let(:digest) { create(:yearly_digest, user: user) }

    describe '#sharing_enabled?' do
      context 'when sharing_settings is nil' do
        before { digest.update_column(:sharing_settings, nil) }

        it 'returns false' do
          expect(digest.sharing_enabled?).to be false
        end
      end

      context 'when sharing_settings is empty hash' do
        before { digest.update(sharing_settings: {}) }

        it 'returns false' do
          expect(digest.sharing_enabled?).to be false
        end
      end

      context 'when enabled is false' do
        before { digest.update(sharing_settings: { 'enabled' => false }) }

        it 'returns false' do
          expect(digest.sharing_enabled?).to be false
        end
      end

      context 'when enabled is true' do
        before { digest.update(sharing_settings: { 'enabled' => true }) }

        it 'returns true' do
          expect(digest.sharing_enabled?).to be true
        end
      end

      context 'when enabled is a string "true"' do
        before { digest.update(sharing_settings: { 'enabled' => 'true' }) }

        it 'returns false (strict boolean check)' do
          expect(digest.sharing_enabled?).to be false
        end
      end
    end

    describe '#sharing_expired?' do
      context 'when sharing_settings is nil' do
        before { digest.update_column(:sharing_settings, nil) }

        it 'returns false' do
          expect(digest.sharing_expired?).to be false
        end
      end

      context 'when expiration is blank' do
        before { digest.update(sharing_settings: { 'enabled' => true }) }

        it 'returns false' do
          expect(digest.sharing_expired?).to be false
        end
      end

      context 'when expiration is present but expires_at is blank' do
        before do
          digest.update(sharing_settings: {
            'enabled' => true,
            'expiration' => '1h'
          })
        end

        it 'returns true' do
          expect(digest.sharing_expired?).to be true
        end
      end

      context 'when expires_at is in the future' do
        before do
          digest.update(sharing_settings: {
            'enabled' => true,
            'expiration' => '1h',
            'expires_at' => 1.hour.from_now.iso8601
          })
        end

        it 'returns false' do
          expect(digest.sharing_expired?).to be false
        end
      end

      context 'when expires_at is in the past' do
        before do
          digest.update(sharing_settings: {
            'enabled' => true,
            'expiration' => '1h',
            'expires_at' => 1.hour.ago.iso8601
          })
        end

        it 'returns true' do
          expect(digest.sharing_expired?).to be true
        end
      end

      context 'when expires_at is invalid date string' do
        before do
          digest.update(sharing_settings: {
            'enabled' => true,
            'expiration' => '1h',
            'expires_at' => 'invalid-date'
          })
        end

        it 'returns true (treats as expired)' do
          expect(digest.sharing_expired?).to be true
        end
      end
    end

    describe '#public_accessible?' do
      context 'when sharing_settings is nil' do
        before { digest.update_column(:sharing_settings, nil) }

        it 'returns false' do
          expect(digest.public_accessible?).to be false
        end
      end

      context 'when sharing is not enabled' do
        before { digest.update(sharing_settings: { 'enabled' => false }) }

        it 'returns false' do
          expect(digest.public_accessible?).to be false
        end
      end

      context 'when sharing is enabled but expired' do
        before do
          digest.update(sharing_settings: {
            'enabled' => true,
            'expiration' => '1h',
            'expires_at' => 1.hour.ago.iso8601
          })
        end

        it 'returns false' do
          expect(digest.public_accessible?).to be false
        end
      end

      context 'when sharing is enabled and not expired' do
        before do
          digest.update(sharing_settings: {
            'enabled' => true,
            'expiration' => '1h',
            'expires_at' => 1.hour.from_now.iso8601
          })
        end

        it 'returns true' do
          expect(digest.public_accessible?).to be true
        end
      end

      context 'when sharing is enabled with no expiration' do
        before do
          digest.update(sharing_settings: { 'enabled' => true })
        end

        it 'returns true' do
          expect(digest.public_accessible?).to be true
        end
      end
    end

    describe '#enable_sharing!' do
      it 'enables sharing with default 24h expiration' do
        digest.enable_sharing!

        expect(digest.sharing_enabled?).to be true
        expect(digest.sharing_settings['expiration']).to eq('24h')
        expect(digest.sharing_uuid).to be_present
      end

      it 'enables sharing with custom expiration' do
        digest.enable_sharing!(expiration: '1h')

        expect(digest.sharing_settings['expiration']).to eq('1h')
      end

      it 'defaults to 24h for invalid expiration' do
        digest.enable_sharing!(expiration: 'invalid')

        expect(digest.sharing_settings['expiration']).to eq('24h')
      end
    end

    describe '#disable_sharing!' do
      before { digest.enable_sharing! }

      it 'disables sharing' do
        digest.disable_sharing!

        expect(digest.sharing_enabled?).to be false
        expect(digest.sharing_settings['expiration']).to be_nil
      end
    end

    describe '#generate_new_sharing_uuid!' do
      it 'generates a new UUID' do
        old_uuid = digest.sharing_uuid
        digest.generate_new_sharing_uuid!

        expect(digest.sharing_uuid).not_to eq(old_uuid)
      end
    end
  end

  describe 'DistanceConvertible' do
    let(:user) { create(:user) }
    let(:digest) { create(:yearly_digest, user: user, distance: 10_000) } # 10 km

    describe '#distance_in_unit' do
      it 'converts distance to kilometers' do
        expect(digest.distance_in_unit('km')).to eq(10.0)
      end

      it 'converts distance to miles' do
        expect(digest.distance_in_unit('mi').round(2)).to eq(6.21)
      end
    end

    describe '.convert_distance' do
      it 'converts distance to kilometers' do
        expect(described_class.convert_distance(10_000, 'km')).to eq(10.0)
      end
    end
  end
end
