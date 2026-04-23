# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ClearUserJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'is enqueued in the archival queue' do
      expect { described_class.perform_later(user.id) }
        .to have_enqueued_job.on_queue('archival')
    end

    context 'when user does not exist' do
      it 'skips without error' do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end
    end

    context 'when user has verified archives with uncleared points' do
      let!(:archive) do
        create(:points_raw_data_archive, user: user, verified_at: Time.current)
      end
      let!(:point) do
        create(:point, user: user, raw_data_archived: true,
                       raw_data_archive_id: archive.id,
                       raw_data: { 'foo' => 'bar' })
      end

      it 'clears raw_data on points with verified archives' do
        described_class.perform_now(user.id)

        expect(point.reload.raw_data).to eq({})
      end
    end

    context 'when user has unverified archives' do
      let!(:archive) do
        create(:points_raw_data_archive, user: user, verified_at: nil)
      end
      let!(:point) do
        create(:point, user: user, raw_data_archived: true,
                       raw_data_archive_id: archive.id,
                       raw_data: { 'foo' => 'bar' })
      end

      it 'does not clear raw_data' do
        described_class.perform_now(user.id)

        expect(point.reload.raw_data).to eq({ 'foo' => 'bar' })
      end
    end

    context 'when advisory lock is held' do
      it 'skips without error' do
        allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(false)

        expect { described_class.perform_now(user.id) }.not_to raise_error
      end
    end

    context 'metric emissions' do
      let!(:archive) do
        create(:points_raw_data_archive, user: user, verified_at: Time.current)
      end
      let!(:point) do
        create(:point, user: user, raw_data_archived: true,
                       raw_data_archive_id: archive.id,
                       raw_data: { 'foo' => 'bar' })
      end

      it 'increments operations_total with clear/success tags' do
        expect do
          described_class.perform_now(user.id)
        end.to increment_yabeda_counter(Yabeda.dawarich_archive.operations_total)
          .with_tags(operation: 'clear', status: 'success')
      end

      it 'increments points_total with removed tag' do
        expect do
          described_class.perform_now(user.id)
        end.to increment_yabeda_counter(Yabeda.dawarich_archive.points_total)
          .with_tags(operation: 'removed')
      end
    end
  end
end
