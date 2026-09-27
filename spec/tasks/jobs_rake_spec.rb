# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'dawarich:jobs' do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('dawarich:jobs:release') }

  def run(task, *args)
    Rake::Task[task].reenable
    expect { Rake::Task[task].invoke(*args) }.to output.to_stdout
  end

  it 'releases a key to Sidekiq, pinned, and unpins it' do
    job_owner!('cron:app_version_checking_job', :oban)

    run('dawarich:jobs:release', 'cron:app_version_checking_job')
    expect(JobOwnership.with_owner('cron:app_version_checking_job') { :sidekiq_runs }).to eq(:sidekiq_runs)

    run('dawarich:jobs:unpin', 'cron:app_version_checking_job')
    expect(ActiveRecord::Base.connection.select_value(
             "SELECT pinned FROM phoenix.job_owners WHERE key = 'cron:app_version_checking_job'"
           )).to be(false)
  end
end
