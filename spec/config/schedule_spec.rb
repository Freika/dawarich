# frozen_string_literal: true

require 'rails_helper'

# Guards the three-way contract described in .claude/rules/background-jobs.md:
# a cron entry's queue, the job class's `queue_as`, and the queue list in
# config/sidekiq.yml must all agree. A drift in any of them means the job
# either never runs or runs at the wrong priority, and neither failure mode
# surfaces as an exception.
RSpec.describe 'config/schedule.yml' do
  schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
  sidekiq_queues = YAML.load_file(Rails.root.join('config/sidekiq.yml')).fetch(:queues).map(&:to_s)

  it 'is not empty' do
    expect(schedule).not_to be_empty
  end

  schedule.each do |entry_name, config|
    context "entry #{entry_name}" do
      let(:job_class) { config.fetch('class') }
      let(:scheduled_queue) { config['queue'] }

      it 'references a job class that exists' do
        expect { job_class.constantize }.not_to raise_error
      end

      it 'declares a queue' do
        expect(scheduled_queue).to be_present
      end

      it 'schedules onto the queue the job class declares' do
        expect(scheduled_queue).to eq(job_class.constantize.new.queue_name)
      end

      it 'schedules onto a queue Sidekiq actually processes' do
        expect(sidekiq_queues).to include(scheduled_queue)
      end
    end
  end
end
