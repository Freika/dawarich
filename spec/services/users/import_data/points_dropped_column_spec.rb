# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Points do
  subject(:restore) { described_class.new(user, points_data).call }

  let(:user) { create(:user) }

  let(:point_payload) do
    {
      'lonlat' => 'POINT(12.3712 51.3402)',
      'timestamp' => 1_709_287_200,
      'battery' => 80,
      'accuracy' => 5
    }
  end

  context 'when the archive carries a column that no longer exists' do
    let(:points_data) { [point_payload.merge('legacy_removed_column' => 'whatever')] }

    it 'still restores the point' do
      expect { restore }.to change { user.points.count }.by(1)
    end

    it 'ignores the unknown attribute' do
      restore

      expect(user.points.last.timestamp).to eq(1_709_287_200)
    end
  end

  context 'when the archive matches the current schema' do
    let(:points_data) { [point_payload] }

    it 'restores the point' do
      expect { restore }.to change { user.points.count }.by(1)
    end
  end
end
