# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_a5_1b' do
  let(:unlock_emails) do
    ['a51b-unlock@dawarich.test'] + (1..4).map { |number| "a51b-unlock-repeat#{number}@dawarich.test" }
  end

  around do |example|
    original = ENV['E2E_B9_B11_FIXTURES']
    ENV['E2E_B9_B11_FIXTURES'] = '1'
    example.run
  ensure
    ENV['E2E_B9_B11_FIXTURES'] = original
  end

  it 'refuses to seed in production' do
    allow(Rails.env).to receive(:production?).and_return(true)

    expect { Rake::Task['e2e:seed_a5_1b'].execute }.to raise_error(SystemExit)
    expect(User.where(email: 'a51b-onboarding@dawarich.test')).not_to exist
  end

  it 'gives the onboarding user one demo import and no onboarding prompt' do
    Rake::Task['e2e:seed_a5_1b'].execute

    user = User.find_by!(email: 'a51b-onboarding@dawarich.test')
    expect(user.valid_password?('safepassword12')).to be(true)
    expect(user.imports.pluck(:demo)).to eq([true])
    expect(user.settings['onboarding_completed']).to be(true)
  end

  it 'prepares one pending unlock for each of five browser repetitions' do
    Rake::Task['e2e:seed_a5_1b'].execute

    unlock_emails.each do |email|
      user = User.find_by!(email:)
      expect(user.valid_password?('safepassword12')).to be(true)
      expect(user.achievement_unlock_events.pending.pluck(:key)).to eq(['DE'])
    end
  end

  it 'leaves one demo import and one pending unlock per user after a second run' do
    2.times { Rake::Task['e2e:seed_a5_1b'].execute }

    expect(User.find_by!(email: 'a51b-onboarding@dawarich.test').imports.count).to eq(1)
    unlock_emails.each do |email|
      expect(User.find_by!(email:).achievement_unlock_events.pending.count).to eq(1)
    end
  end
end
