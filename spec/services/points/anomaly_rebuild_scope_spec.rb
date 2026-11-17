# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyRebuildScope do
  subject(:scope) { described_class.new(user) }

  let(:user) { create(:user) }

  def flag(time)
    create(:point, user: user, anomaly: true, timestamp: time.to_i, lonlat: 'POINT(13.405 52.52)')
  end

  it 'cannot tell what changed when nothing was remembered' do
    expect(scope.changed_years).to be_nil
  end

  it 'finds nothing changed for a user without anomalies before or after' do
    scope.remember

    expect(scope.changed_years).to eq([])
  end

  it 'reports the years whose flagged points changed' do
    flag(Time.utc(2023, 5, 1))
    cleared = flag(Time.utc(2024, 5, 1))
    scope.remember

    cleared.update!(anomaly: false)
    flag(Time.utc(2025, 5, 1))

    expect(scope.changed_years).to eq([2024, 2025])
  end

  it 'keeps the fingerprint of an earlier run that never finished' do
    flagged = flag(Time.utc(2024, 5, 1))
    scope.remember
    flagged.update!(anomaly: false)

    scope.remember

    expect(scope.changed_years).to eq([2024])
  end

  it 'follows tracks across several New Years' do
    flagged = flag(Time.utc(2024, 5, 1))
    scope.remember
    flagged.update!(anomaly: false)
    create(:track, user: user, start_at: Time.utc(2023, 12, 31, 23), end_at: Time.utc(2024, 1, 1, 1))
    create(:track, user: user, start_at: Time.utc(2022, 12, 31, 23), end_at: Time.utc(2023, 1, 1, 1))

    expect(scope.changed_years).to eq([2022, 2023, 2024])
  end

  it 'cannot tell what changed once forgotten' do
    scope.remember
    scope.forget

    expect(scope.changed_years).to be_nil
    expect(user.reload.settings).not_to have_key(described_class::SETTINGS_KEY)
  end
end
