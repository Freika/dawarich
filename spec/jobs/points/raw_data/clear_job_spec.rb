# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ClearJob, type: :job do
  describe '#perform' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    it 'enqueues a ClearUserJob for each user' do
      users = create_list(:user, 2)

      expect { described_class.perform_now }.to have_enqueued_job(Points::RawData::ClearUserJob).exactly(2).times

      users.each do |user|
        expect(Points::RawData::ClearUserJob).to have_been_enqueued.with(user.id)
      end
    end

    context 'when ARCHIVE_RAW_DATA is not true' do
      before do
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('false')
      end

      it 'does not enqueue any jobs' do
        create(:user)

        expect { described_class.perform_now }.not_to have_enqueued_job(Points::RawData::ClearUserJob)
      end
    end
  end
end
