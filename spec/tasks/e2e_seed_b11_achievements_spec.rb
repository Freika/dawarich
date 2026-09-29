# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_b11_achievements' do
  let(:collection_user) { User.find_by!(email: 'b11-collection@dawarich.test') }

  around do |example|
    original = ENV['E2E_B9_B11_FIXTURES']
    ENV['E2E_B9_B11_FIXTURES'] = '1'
    example.run
  ensure
    ENV['E2E_B9_B11_FIXTURES'] = original
  end

  after { Flipper.disable(:achievements) }

  it 'refuses to seed in production before changing the achievement flag' do
    allow(Rails.env).to receive(:production?).and_return(true)

    expect { Rake::Task['e2e:seed_b11_achievements'].execute }.to raise_error(SystemExit)
    expect(Flipper.enabled?(:achievements)).to be(false)
  end

  it 'enables the flag and creates one synthetic exploration record' do
    Rake::Task['e2e:seed_b11_achievements'].execute

    progress = collection_user.achievement_progresses.find_by!(achievement_key: 'exploration')
    expect(Flipper.enabled?(:achievements)).to be(true)
    expect(progress.state.fetch('earned').keys).to contain_exactly('DE', 'DE-BY')
    expect(progress.state['calculation_version']).to eq(Achievements::RegionSetChecker::CALCULATION_VERSION)
  end

  it 'replaces the same record on another run' do
    Rake::Task['e2e:seed_b11_achievements'].execute
    Rake::Task['e2e:seed_b11_achievements'].execute

    expect(collection_user.achievement_progresses.where(achievement_key: 'exploration').count).to eq(1)
  end

  it 'leaves the shared demo user achievements unchanged' do
    demo = User.find_by(email: 'demo@dawarich.app') || create(:user, email: 'demo@dawarich.app')
    before = demo.achievement_progresses.count

    Rake::Task['e2e:seed_b11_achievements'].execute

    expect(demo.achievement_progresses.count).to eq(before)
  end

  it 'prepares one pending unlock for a separate synthetic user' do
    Rake::Task['e2e:seed_b11_achievements'].execute

    user = User.find_by!(email: 'b11-unlock@dawarich.test')
    expect(user.valid_password?('safepassword12')).to be(true)
    expect(user.achievement_progresses.find_by!(achievement_key: 'exploration').state.fetch('earned')).to have_key('DE')
    expect(user.achievement_unlock_events.pending.pluck(:key)).to eq(['DE'])
  end

  it 'prepares independent unlock events for five browser repetitions' do
    Rake::Task['e2e:seed_b11_achievements'].execute

    1.upto(4) do |number|
      user = User.find_by!(email: "b11-unlock-repeat#{number}@dawarich.test")
      expect(user.achievement_unlock_events.pending.pluck(:key)).to eq(['DE'])
    end
  end
end
