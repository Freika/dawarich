# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyBackfillJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let!(:empty_user) { create(:user) }

    before { create(:point, user: user) }

    it 'enqueues per-user jobs for users with points' do
      expect { described_class.new.perform }
        .to have_enqueued_job(Points::AnomalyBackfillUserJob)
        .with(user.id)
    end

    it 'skips users with no points' do
      expect { described_class.new.perform }
        .not_to have_enqueued_job(Points::AnomalyBackfillUserJob)
        .with(empty_user.id)
    end
  end

  describe 'queue configuration' do
    it 'uses the low_priority queue' do
      expect(described_class.queue_name).to eq('low_priority')
    end
  end
end
