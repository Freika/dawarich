# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Trial::CalculatingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user, :trial, skip_auto_trial: true, active_until: 1.day.from_now) }

    it 'runs on the digests queue' do
      expect(described_class.new.queue_name).to eq('digests')
    end

    it 'persists a weekly digest covering the trial week' do
      expect { described_class.perform_now(user.id) }.to change { Users::Digest.weekly.count }.by(1)
    end

    it 'covers the seven days leading up to the trial end' do
      described_class.perform_now(user.id)
      digest = Users::Digest.weekly.last

      expect(digest.year).to eq(Date.current.cwyear)
      expect(digest.week).to eq(Date.current.cweek)
    end

    it 'does not send any email from Dawarich' do
      expect { described_class.perform_now(user.id) }.not_to(change { ActionMailer::Base.deliveries.count })
    end

    it 'no-ops when the user no longer exists' do
      missing_id = user.id
      user.destroy!

      expect { described_class.perform_now(missing_id) }.not_to raise_error
    end

    it 'no-ops when the user has no active_until' do
      undated = create(:user, :trial, skip_auto_trial: true, active_until: nil)

      expect { described_class.perform_now(undated.id) }.not_to(change { Users::Digest.weekly.count })
    end

    it 'is idempotent across repeated runs' do
      described_class.perform_now(user.id)

      expect { described_class.perform_now(user.id) }.not_to(change { Users::Digest.weekly.count })
    end
  end
end
