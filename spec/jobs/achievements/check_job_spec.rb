# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::CheckJob do
  let(:user) { create(:user) }

  before { Flipper.enable(:achievements) }

  after { Flipper.disable(:achievements) }

  it 'runs the checker for the user' do
    checker = instance_double(Achievements::RegionSetChecker, call: nil)
    allow(Achievements::RegionSetChecker).to receive(:new)
      .with(user, notify: false, oldest_timestamp: nil).and_return(checker)

    described_class.perform_now(user.id, notify: false)

    expect(checker).to have_received(:call)
  end

  it 'forwards the oldest timestamp to the checker' do
    checker = instance_double(Achievements::RegionSetChecker, call: nil)
    allow(Achievements::RegionSetChecker).to receive(:new)
      .with(user, notify: true, oldest_timestamp: 123).and_return(checker)

    described_class.perform_now(user.id, oldest_timestamp: 123)

    expect(checker).to have_received(:call)
  end

  it 'does nothing for a missing user' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'skips computation entirely while the feature flag is disabled' do
    Flipper.disable(:achievements)
    create(:point, user: user, timestamp: 1)

    described_class.perform_now(user.id, notify: true)

    expect(Achievements::Progress.where(user: user)).to be_empty
  end

  it 'still computes for a forced backfill while the feature flag is disabled' do
    Flipper.disable(:achievements)
    create(:point, user: user, timestamp: 1)

    described_class.perform_now(user.id, notify: false, force: true)

    expect(Achievements::Progress.where(user: user)).to be_present
  end
end
