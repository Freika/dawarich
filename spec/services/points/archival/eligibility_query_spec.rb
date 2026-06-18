# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::EligibilityQuery do
  let(:dormant) do
    create(:user, skip_auto_trial: true, status: :inactive, active_until: 2.years.ago,
                  last_sign_in_at: 1.year.ago, points_count: 100)
  end

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  it 'includes dormant, access-lapsed users with points' do
    expect(described_class.new.candidates).to include(dormant)
  end

  it 'excludes users with active access' do
    paying = create(:user, skip_auto_trial: true, active_until: 1.year.from_now,
                           last_sign_in_at: 1.year.ago, points_count: 100)
    expect(described_class.new.candidates).not_to include(paying)
  end

  it 'excludes recently active users' do
    recent = create(:user, skip_auto_trial: true, active_until: 2.years.ago,
                           last_sign_in_at: 1.day.ago, points_count: 100)
    expect(described_class.new.candidates).not_to include(recent)
  end

  it 'excludes users mid-signup (pending_payment)' do
    pending = create(:user, skip_auto_trial: true, status: :pending_payment, active_until: nil,
                            last_sign_in_at: 1.year.ago, points_count: 100)
    expect(described_class.new.candidates).not_to include(pending)
  end

  it 'excludes already-archived users' do
    archived = create(:user, skip_auto_trial: true, status: :inactive, active_until: 2.years.ago,
                             last_sign_in_at: 1.year.ago, points_count: 100,
                             points_archive_state: :archived)
    expect(described_class.new.candidates).not_to include(archived)
  end

  it 'returns nothing on self-hosted' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    dormant
    expect(described_class.new.candidates).to be_empty
  end
end
