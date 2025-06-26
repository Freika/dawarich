# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Areas, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe '#call' do
    context 'when user has no areas' do
      it 'returns an empty array' do
        result = service.call
        expect(result).to eq([])
      end
    end

    context 'when user has areas' do
      let!(:area1) { create(:area, user: user, name: 'Home', radius: 100) }
      let!(:area2) { create(:area, user: user, name: 'Work', radius: 200) }

      it 'returns all user areas' do
        result = service.call
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
      end

      it 'excludes user_id and id fields' do
        result = service.call

        result.each do |area_data|
          expect(area_data).not_to have_key('user_id')
          expect(area_data).not_to have_key('id')
        end
      end

      it 'includes expected area attributes' do
        result = service.call
        area_data = result.find { |a| a['name'] == 'Home' }

        expect(area_data).to include(
          'name' => 'Home',
          'radius' => 100
        )
        expect(area_data).to have_key('created_at')
        expect(area_data).to have_key('updated_at')
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_area) { create(:area, user: user, name: 'User Area') }
      let!(:other_user_area) { create(:area, user: other_user, name: 'Other User Area') }

      it 'only returns areas for the specified user' do
        result = service.call
        expect(result.size).to eq(1)
        expect(result.first['name']).to eq('User Area')
      end
    end
  end

  describe 'private methods' do
    describe '#user' do
      it 'returns the initialized user' do
        expect(service.send(:user)).to eq(user)
      end
    end
  end
end
