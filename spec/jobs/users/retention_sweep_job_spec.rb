# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::RetentionSweepJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user).tap do |u|
      u.update_columns(status: User.statuses[:inactive], active_until: Time.zone.local(2025, 6, 1))
    end
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user
  end

  def run_on(year, month, day)
    travel_to(Time.zone.local(year, month, day, 4)) { described_class.perform_now }
  end

  def warning_for(deletion_on)
    have_enqueued_job(Users::MailerSendingJob).with(user.id, 'account_deletion_warning', deletion_on:)
  end

  def retention_state
    user.reload.settings['retention']
  end

  it 'does nothing on a self-hosted instance' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    expect { run_on(2026, 12, 2) }.not_to have_enqueued_job(Users::MailerSendingJob)
    expect(retention_state).to be_nil
  end

  it 'sends nothing more than 30 days before deletion' do
    expect { run_on(2026, 12, 1) }.not_to have_enqueued_job(Users::MailerSendingJob)
  end

  it 'sends the 30-day warning and promises the launch date' do
    expect { run_on(2026, 12, 2) }.to warning_for('2027-01-01')
    expect(retention_state['deletion_on']).to eq('2027-01-01')
  end

  it 'does not send the same stage twice' do
    run_on(2026, 12, 2)

    expect { run_on(2026, 12, 2) }.not_to have_enqueued_job(Users::MailerSendingJob)
  end

  it 'sends the 7-day and the 1-day warnings on their days' do
    run_on(2026, 12, 2)

    expect { run_on(2026, 12, 25) }.to warning_for('2027-01-01')
    expect { run_on(2026, 12, 30) }.not_to have_enqueued_job(Users::MailerSendingJob)
    expect { run_on(2026, 12, 31) }.to warning_for('2027-01-01')
  end

  it 'soft-deletes the account and queues its destruction on the archival queue on the deletion day' do
    run_on(2026, 12, 2)

    expect { run_on(2027, 1, 1) }.to have_enqueued_job(Users::DestroyJob).with(user.id).on_queue('archival')
    expect(user.reload.deleted?).to be true
  end

  it 'sends no warning on the deletion day itself' do
    run_on(2026, 12, 2)

    expect { run_on(2027, 1, 1) }.not_to have_enqueued_job(Users::MailerSendingJob)
  end

  it 'gives a full 30 days to an account warned late' do
    expect { run_on(2027, 1, 1) }.to warning_for('2027-01-31')
    expect(user.reload.deleted?).to be false

    expect { run_on(2027, 1, 30) }.not_to have_enqueued_job(Users::DestroyJob)
    expect { run_on(2027, 1, 31) }.to have_enqueued_job(Users::DestroyJob).with(user.id)
  end

  it 'sends only the latest due stage when several are due' do
    run_on(2026, 12, 2)

    expect { run_on(2026, 12, 31) }.to have_enqueued_job(Users::MailerSendingJob).exactly(:once)
    expect(retention_state['sent'].keys).to contain_exactly('30d', '7d', '1d')
  end

  it 'starts over when the account lapsed again after resubscribing' do
    run_on(2026, 12, 2)
    user.update_columns(active_until: Time.zone.local(2026, 2, 10))

    expect { run_on(2027, 1, 15) }.to warning_for('2027-02-14')
    expect(user.reload.deleted?).to be false
  end

  it 'forgets the schedule of an account whose access came back' do
    run_on(2026, 12, 2)
    user.update_columns(status: User.statuses[:active], active_until: Time.zone.local(2027, 3, 1))

    run_on(2027, 1, 1)

    expect(retention_state).to be_nil
  end

  it 'warns again before deleting an account that lapsed again onto the same computed date' do
    user.update_columns(created_at: Time.zone.local(2025, 1, 1))
    run_on(2026, 12, 2)
    user.update_columns(status: User.statuses[:active], active_until: Time.zone.local(2027, 1, 20))
    run_on(2027, 1, 1)
    user.update_columns(status: User.statuses[:inactive], active_until: nil)

    expect { run_on(2027, 2, 11) }.to warning_for('2027-03-13')
    expect(user.reload.deleted?).to be false
  end

  it 'does not delete an account that resubscribed after the run picked it up' do
    run_on(2026, 12, 2)
    stale = Users::RetentionCandidatesQuery.new(today: Date.new(2027, 1, 1)).call.find(user.id)
    user.update_columns(status: User.statuses[:active], active_until: Time.zone.local(2028, 1, 1))
    loaded_before_resubscribing = double('candidates')
    allow(loaded_before_resubscribing).to receive(:find_each).and_yield(stale)
    allow(Users::RetentionCandidatesQuery).to receive(:new)
      .and_return(instance_double(Users::RetentionCandidatesQuery, call: loaded_before_resubscribing))

    expect { run_on(2027, 1, 1) }.not_to have_enqueued_job(Users::DestroyJob)
    expect(user.reload.deleted?).to be false
  end

  it 'keeps sweeping the other accounts when one of them fails' do
    other = create(:user).tap do |u|
      u.update_columns(status: User.statuses[:inactive], active_until: Time.zone.local(2025, 6, 1))
    end
    allow(Users::MailerSendingJob).to receive(:perform_later).and_wrap_original do |original, user_id, *args, **kwargs|
      raise 'mail queue down' if user_id == user.id

      original.call(user_id, *args, **kwargs)
    end
    allow(ExceptionReporter).to receive(:call)

    run_on(2026, 12, 2)

    expect(other.reload.settings.dig('retention', 'deletion_on')).to eq('2027-01-01')
    expect(ExceptionReporter).to have_received(:call).with(instance_of(RuntimeError), /user_id=#{user.id}/)
  end

  it 'leaves the other settings untouched' do
    user.update_columns(settings: user.settings.merge('timezone' => 'Asia/Tokyo'))

    run_on(2026, 12, 2)

    expect(user.reload.settings['timezone']).to eq('Asia/Tokyo')
  end

  context 'when the account owns a family with other members' do
    let!(:family) { create(:family, creator: user) }
    let!(:member_membership) { create(:family_membership, family:, user: create(:user), role: :member) }

    before { create(:family_membership, family:, user:, role: :owner) }

    it 'neither warns nor deletes the owner while the members stay' do
      expect { run_on(2026, 12, 2) }.not_to have_enqueued_job(Users::MailerSendingJob)
      expect { run_on(2027, 1, 1) }.not_to have_enqueued_job(Users::DestroyJob)
      expect(user.reload.deleted?).to be false
    end

    it 'gives the owner a full notice once the members are gone' do
      run_on(2027, 1, 1)
      member_membership.destroy!

      expect { run_on(2027, 1, 2) }.to warning_for('2027-02-01')
      expect { run_on(2027, 1, 31) }.not_to have_enqueued_job(Users::DestroyJob)
      expect { run_on(2027, 2, 1) }.to have_enqueued_job(Users::DestroyJob).with(user.id)
    end

    it 'forgets a schedule promised before the members joined' do
      member_membership.destroy!
      run_on(2026, 12, 2)
      create(:family_membership, family:, user: create(:user), role: :member)

      run_on(2027, 1, 1)

      expect(retention_state).to be_nil
    end
  end
end
