require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:imports).dependent(:destroy) }
    it { is_expected.to have_many(:points).through(:imports) }
    it { is_expected.to have_many(:stats) }
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

    xdescribe '#export_data' do
      subject { user.export_data }

      let(:import) { create(:import, user: user) }
      let(:point) { create(:point, import: import) }

      it 'returns json' do
        expect(subject).to include(user.email)
        expect(subject).to include('dawarich-export')
        expect(subject).to include(point.attributes.except('raw_data', 'id', 'created_at', 'updated_at', 'country', 'city', 'import_id').to_json)
      end
    end

    describe '#total_km' do
      subject { user.total_km }

      let!(:stat_1) { create(:stat, user: user, distance: 10) }
      let!(:stat_2) { create(:stat, user: user, distance: 20) }

      it 'returns sum of distances' do
        expect(subject).to eq(30)
      end
    end

    describe '#total_countries' do
      subject { user.total_countries }

      let!(:stat) { create(:stat, user: user, toponyms: [{ 'country' => 'Country' }]) }

      it 'returns number of countries' do
        expect(subject).to eq(1)
      end
    end

    describe '#total_cities' do
      subject { user.total_cities }

      let!(:stat) { create(:stat, user: user, toponyms: [{ 'city' => 'City' }]) }

      it 'returns number of cities' do
        expect(subject).to eq(1)
      end
    end

    describe '#total_reverse_geocoded' do
      subject { user.total_reverse_geocoded }

      let(:import) { create(:import, user: user) }
      let!(:point) { create(:point, country: 'Country', city: 'City', import: import) }

      it 'returns number of reverse geocoded points' do
        expect(subject).to eq(1)
      end
    end
  end
end
