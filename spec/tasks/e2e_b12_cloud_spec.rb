# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'e2e:b12:user' do
  it 'refuses a database outside the isolated B12 names' do
    original = ENV['DATABASE_NAME']
    ENV['DATABASE_NAME'] = 'dawarich_test'
    expect { Rake::Task['e2e:b12:user'].invoke('b12-guard@example.test', 'lite') }.to raise_error(SystemExit)
  ensure
    ENV['DATABASE_NAME'] = original
    Rake::Task['e2e:b12:user'].reenable if Rake::Task.task_defined?('e2e:b12:user')
  end
end
