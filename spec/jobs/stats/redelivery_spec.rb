# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stats and digest execution redelivery', type: :job do
  [Stats::CalculatingJob, Users::Digests::Monthly::CalculatingJob,
   Users::Digests::Yearly::CalculatingJob].each do |job_class|
    context job_class.name do
      let(:job_class) { job_class }
      let!(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }
      let!(:stat) { create(:stat, user:, year: 2024, month: 3, distance: 6968) }
      let(:serialized) do
        args = job_class == Users::Digests::Yearly::CalculatingJob ? [user.id, 2024] : [user.id, 2024, 3]
        job = job_class == Stats::CalculatingJob ? job_class.new(*args, notify_on_failure: false) : job_class.new(*args)
        job.serialize
      end

      before do
        job_owner!(job_class::OWNER_KEY, :sidekiq, pinned: true)
        allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_wrap_original do |original|
          @calls = (@calls || 0) + 1
          original.call
        end
      end

      it 'Rails same_job_redelivery preserves the completed calculation', :rxstats_redelivery do
        identity = Stats::EffectReceipts.id('00000000-0000-4000-8000-000000000001',
                                            'stats.calculate_month', 14_101, 2025, 3)
        expect(identity).to eq('faeefa31-e5b4-54b7-ab80-994733839961')
        ActiveJob::Base.deserialize(serialized).perform_now
        expect(stat.reload.distance).to eq(0)
        stat.update_columns(distance: 9876)
        ActiveJob::Base.deserialize(serialized).perform_now

        expect(@calls).to eq(job_class == Users::Digests::Yearly::CalculatingJob ? 12 : 1)
        expect(stat.reload.distance).to eq(9876)
      end

      it 'Rails ownership_flip does not forward already executed work', :rxstats_flip do
        ActiveJob::Base.deserialize(serialized).perform_now
        stat.update_columns(distance: 9876)
        job_owner!(job_class::OWNER_KEY, :oban, pinned: true)
        ActiveJob::Base.deserialize(serialized).perform_now

        expect(JobOutbox.where(event_id: serialized.fetch('job_id'))).to be_empty
        expect(@calls).to eq(job_class == Users::Digests::Yearly::CalculatingJob ? 12 : 1)
        expect(stat.reload.distance).to eq(9876)
      end
    end
  end

  it 'Rails digest terminal publication remains durable after enqueue failure', :rxstats_mail_retry do
    user = create(:user, settings: { 'timezone' => 'Etc/UTC' })
    create(:stat, user:, year: 2024, month: 3, distance: 6968)
    [Users::Digests::Monthly::CalculatingJob, Users::Digests::Yearly::CalculatingJob].each do |klass|
      yearly = klass == Users::Digests::Yearly::CalculatingJob
      period = yearly ? 'year' : 'month'
      args = yearly ? [user.id, 2024] : [user.id, 2024, 3]
      mail = yearly ? Users::Digests::Yearly::EmailSendingJob : Users::Digests::Monthly::EmailSendingJob
      job_owner!(klass::OWNER_KEY, :sidekiq, pinned: true)
      serialized = klass.new(*args).serialize
      allow(mail).to receive(:perform_later).and_raise(IOError, 'synthetic mail enqueue failure')
      expect { ActiveJob::Base.deserialize(serialized).perform_now }.to raise_error(IOError)
      count = ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM phoenix.rails_commands WHERE kind='digests.email_#{period}'"
      )
      expect(count).to eq(1)
      allow(mail).to receive(:perform_later).and_call_original
      ActiveJob::Base.deserialize(serialized).perform_now
      expect { RailsCommands::Poller.drain_once }.to have_enqueued_job(mail).with(*args)
      expect(ActiveRecord::Base.connection.select_value(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind='digests.email_#{period}'"
             )).to eq(0)
    end
  end
end
