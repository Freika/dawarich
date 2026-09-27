# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'e2e:b12:user' do
  let(:output_file) { Rails.root.join('tmp/b12-fixtures', "spec-#{SecureRandom.uuid}.json") }
  let(:email) { "spec-#{SecureRandom.hex(5)}@b12.dawarich.test" }
  let(:b12_env) do
    { 'DATABASE_NAME' => 'dawarich_e2e_b12_cloud_test', 'E2E_B12_EGRESS' => '1',
      'B12_FIXTURE_OUTPUT' => output_file.to_s }
  end

  after do
    Rake::Task['e2e:b12:user'].reenable
    FileUtils.rm_f(output_file)
  end

  def refuse(message)
    raise_error(SystemExit, message).and output(/#{message}/).to_stderr
  end

  def invoke_with(env)
    stub_const('ENV', ENV.to_h.merge(env))
    Rake::Task['e2e:b12:user'].invoke(email, 'lite')
  end

  it 'refuses a database outside the isolated B12 names' do
    expect { invoke_with(b12_env.merge('DATABASE_NAME' => 'dawarich_test')) }
      .to refuse('B12 fixtures require an isolated database')
    expect(User.exists?(email: email)).to be(false)
  end

  it 'refuses to run without the egress guard' do
    expect { invoke_with(b12_env.merge('E2E_B12_EGRESS' => '0')) }.to refuse('B12 egress guard is required')
    expect(User.exists?(email: email)).to be(false)
  end

  it 'refuses to run in production' do
    allow(Rails.env).to receive(:production?).and_return(true)

    expect { invoke_with(b12_env) }.to refuse('B12 fixtures require an isolated database')
    expect(User.exists?(email: email)).to be(false)
  end

  it 'writes fixture credentials only to a stack-local private file' do
    expect { invoke_with(b12_env) }.not_to output.to_stdout
    expect(JSON.parse(output_file.read).fetch('email')).to eq(email)
    expect(File.stat(output_file).mode & 0o777).to eq(0o600)
  end
end

RSpec.describe 'e2e:b12:registration' do
  let(:output_files) { [] }

  after do
    Rails.cache.delete(E2eB12Fixtures::REGISTRATION_KEY)
    output_files.each { |file| FileUtils.rm_f(file) }
  end

  def switch_registration(value)
    output_file = Rails.root.join('tmp/b12-fixtures', "spec-#{SecureRandom.uuid}.json")
    output_files << output_file
    stub_const('ENV', ENV.to_h.merge('DATABASE_NAME' => 'dawarich_e2e_b12_cloud_test', 'E2E_B12_EGRESS' => '1',
                                     'B12_FIXTURE_OUTPUT' => output_file.to_s))
    Rake::Task['e2e:b12:registration'].invoke(value)
    JSON.parse(output_file.read)
  ensure
    Rake::Task['e2e:b12:registration'].reenable
  end

  it 'reports the stored switch and restores the unset default' do
    expect(switch_registration('false')).to eq('registration_enabled' => false)

    expect(switch_registration('default')).to eq('registration_enabled' => nil)
    expect(Rails.cache.exist?(E2eB12Fixtures::REGISTRATION_KEY)).to be(false)
  end
end
