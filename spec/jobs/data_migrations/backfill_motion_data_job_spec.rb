# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillMotionDataJob do
  describe '#perform' do
    let(:user) { create(:user) }

    context 'with Overland raw_data' do
      let!(:point) do
        create(:point, user: user, motion_data: {},
                       raw_data: { 'properties' => { 'motion' => ['driving'], 'activity' => 'other_navigation' } })
      end

      it 'backfills motion_data from raw_data' do
        described_class.new.perform

        point.reload
        expect(point.motion_data).to eq({ 'motion' => ['driving'], 'activity' => 'other_navigation' })
      end
    end

    context 'with Google raw_data' do
      let!(:point) do
        create(:point, user: user, motion_data: {},
                       raw_data: { 'activityRecord' => { 'probableActivities' => [{ 'type' => 'WALKING' }] } })
      end

      it 'backfills motion_data from raw_data' do
        described_class.new.perform

        point.reload
        expect(point.motion_data).to eq({ 'activityRecord' => { 'probableActivities' => [{ 'type' => 'WALKING' }] } })
      end
    end

    context 'with OwnTracks raw_data' do
      let!(:point) do
        create(:point, user: user, motion_data: {},
                       raw_data: { 'm' => 1, '_type' => 'location', 'lat' => 52.0, 'lon' => 13.0 })
      end

      it 'backfills motion_data from raw_data' do
        described_class.new.perform

        point.reload
        expect(point.motion_data).to eq({ 'm' => 1, '_type' => 'location' })
      end
    end

    context 'with empty raw_data' do
      let!(:point) { create(:point, user: user, motion_data: {}, raw_data: {}) }

      it 'skips points with empty raw_data' do
        described_class.new.perform

        point.reload
        expect(point.motion_data).to eq({})
      end
    end

    context 'when motion_data already populated' do
      let!(:point) do
        create(:point, user: user,
                       motion_data: { 'motion' => ['walking'] },
                       raw_data: { 'properties' => { 'motion' => ['driving'] } })
      end

      it 'does not overwrite existing motion_data' do
        described_class.new.perform

        point.reload
        expect(point.motion_data).to eq({ 'motion' => ['walking'] })
      end
    end
  end
end
