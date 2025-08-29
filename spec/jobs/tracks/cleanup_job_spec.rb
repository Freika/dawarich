# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::CleanupJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform' do
    context 'with old untracked points' do
      let!(:old_points) do
        create_points_around(user: user, count: 1, base_lat: 20.0, timestamp: 2.days.ago.to_i)
        create_points_around(user: user, count: 1, base_lat: 20.0, timestamp: 1.day.ago.to_i)
      end
      let!(:recent_points) do
        create_points_around(user: user, count: 2, base_lat: 20.0, timestamp: 1.hour.ago.to_i)
      end
      let(:generator) { instance_double(Tracks::Generator) }

      it 'processes only old untracked points' do
        expect(Tracks::Generator).to receive(:new)
          .and_return(generator)

        expect(generator).to receive(:call)

        described_class.new.perform(older_than: 1.day.ago)
      end
    end

    context 'with users having insufficient points' do
      let!(:single_point) do
        create_points_around(user: user, count: 1, base_lat: 20.0, timestamp: 2.days.ago.to_i)
      end

      it 'skips users with less than 2 points' do
        expect(Tracks::Generator).not_to receive(:new)

        described_class.new.perform(older_than: 1.day.ago)
      end
    end

    context 'with no old untracked points' do
      let(:track) { create(:track, user: user) }
      let!(:tracked_points) do
        create_points_around(user: user, count: 3, base_lat: 20.0, timestamp: 2.days.ago.to_i, track: track)
      end

      it 'does not process any users' do
        expect(Tracks::Generator).not_to receive(:new)

        described_class.new.perform(older_than: 1.day.ago)
      end
    end

    context 'with custom older_than parameter' do
      let!(:points) do
        create_points_around(user: user, count: 3, base_lat: 20.0, timestamp: 3.days.ago.to_i)
      end
      let(:generator) { instance_double(Tracks::Generator) }

      it 'uses custom threshold' do
        expect(Tracks::Generator).to receive(:new)
          .and_return(generator)

        expect(generator).to receive(:call)

        described_class.new.perform(older_than: 2.days.ago)
      end
    end
  end

  describe 'job configuration' do
    it 'uses tracks queue' do
      expect(described_class.queue_name).to eq('tracks')
    end

    it 'does not retry on failure' do
      expect(described_class.sidekiq_options_hash['retry']).to be false
    end
  end
end
