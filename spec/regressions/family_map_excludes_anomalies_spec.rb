# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family map excludes points flagged as anomalies' do
  let(:owner) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let(:real_at) { 2.hours.ago.to_i }
  let(:anomaly_at) { 1.hour.ago.to_i }

  before do
    create(:family_membership, user: owner, family: family, role: :owner)
    owner.update_family_location_sharing!(true, share_history: true, history_window: 'all')
    owner.settings['family']['location_sharing']['started_at'] = 1.day.ago.iso8601
    owner.save!

    create(:point, user: owner, timestamp: real_at)
    create(:point, user: owner, timestamp: anomaly_at).update_column(:anomaly, true)
  end

  it 'keeps the member marker on the latest non-anomalous point' do
    expect(owner.latest_location_for_family[:timestamp]).to eq(real_at)
  end

  it 'reports the latest non-anomalous point through the family locations API' do
    expect(Families::Locations.new(owner).call.first[:timestamp]).to eq(real_at)
  end

  it 'leaves anomalies out of the shared history trail' do
    history = Families::Locations.new(owner).history(start_at: 1.day.ago, end_at: Time.current)

    expect(history.first[:points].map(&:last)).to eq([real_at])
  end
end
