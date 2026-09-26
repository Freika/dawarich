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

  it 'writes fixture credentials only to a stack-local private file' do
    output_file = Rails.root.join('tmp/b12-fixtures', "spec-#{SecureRandom.uuid}.json")
    ENV['B12_FIXTURE_OUTPUT'] = output_file.to_s
    email = "spec-#{SecureRandom.hex(5)}@b12.dawarich.test"

    expect { Rake::Task['e2e:b12:user'].invoke(email, 'lite') }.not_to output.to_stdout
    expect(JSON.parse(output_file.read).fetch('email')).to eq(email)
    expect(File.stat(output_file).mode & 0o777).to eq(0o600)
  ensure
    ENV.delete('B12_FIXTURE_OUTPUT')
    File.delete(output_file) if output_file&.exist?
    Rake::Task['e2e:b12:user'].reenable if Rake::Task.task_defined?('e2e:b12:user')
  end
end
