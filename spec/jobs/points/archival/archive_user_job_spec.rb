# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::ArchiveUserJob do
  let(:user) do
    create(:user, skip_auto_trial: true, status: :inactive, active_until: 2.years.ago,
                  last_sign_in_at: 1.year.ago)
  end

  before do
    Flipper.enable(:points_archival)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    create_list(:point, 2, user:, timestamp: Time.utc(2024, 5, 10).to_i,
                           created_at: 1.year.ago)
    user.update_column(:points_count, 2)
  end

  after { Flipper.disable(:points_archival) }

  it 'archives the user and marks state archived' do
    described_class.new.perform(user.id)

    expect(Points::Archive.where(user_id: user.id).verified.count).to be_positive
    expect(user.reload.points_archive_state_archived?).to be(true)
    expect(user.points_archived_at).to be_present
  end

  it 'skips users with recently ingested points' do
    create(:point, user:, timestamp: Time.utc(2024, 5, 11).to_i, created_at: 1.day.ago)

    described_class.new.perform(user.id)
    expect(user.reload.points_archive_state_active?).to be(true)
    expect(Points::Archive.where(user_id: user.id)).to be_empty
  end

  it 'resets state to active and cleans up archives if archiving fails partway' do
    allow_any_instance_of(Points::Archival::Archiver).to receive(:archive_user).and_raise(StandardError, 'boom')
    expect { described_class.new.perform(user.id) }.to raise_error(StandardError)
    expect(user.reload.points_archive_state_active?).to be(true)
    expect(Points::Archive.where(user_id: user.id, deleted_at: nil)).to be_empty
  end

  it 'does nothing when the points_archival flag is disabled' do
    Flipper.disable(:points_archival)

    described_class.new.perform(user.id)

    expect(user.reload.points_archive_state_active?).to be(true)
    expect(Points::Archive.where(user_id: user.id)).to be_empty
  end
end
