# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Families::JobCommands' do
  it 'lapse reverse handler resolves current mail owner with source locale and dedupe' do
    user = create(:user)
    family = create(:family)
    payload = { 'user_id' => user.id, 'family_id' => family.id, 'locale' => 'de',
                'lapse_at' => '2026-10-04T12:00:00Z' }
    handler = RailsCommands::Registry.handler('mail.family_lapse')
    expect(handler).to be_present
    expect { handler.call(payload) }
      .to have_enqueued_job(Families::LapseNotificationJob).with(user.id, family.id).exactly(:once)
    expect(enqueued_jobs.last.fetch('locale')).to eq('de')
    clear_enqueued_jobs
    job_owner!('command:mail.family_lapse', :oban)
    2.times { handler.call(payload) }
    expect(JobOutbox.pending.sole).to have_attributes(
      command_type: 'mail.family_lapse', payload: payload,
      dedupe_key: "family-lapse:#{family.id}:#{user.id}:#{payload.fetch('lapse_at')}"
    )
    expect(Families::LapseNotificationJob).not_to have_been_enqueued
    expect { handler.call(payload.merge('user_id' => -1)) }.not_to(change { JobOutbox.count })
  end
  it 'legacy family jobs forward and rehome before any local write' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    owner = create(:user, plan: :family, active_until: 1.day.from_now, skip_auto_trial: true)
    family = create(:family, creator: owner)
    member = create(:user, plan: :lite, status: :inactive, skip_auto_trial: true)
    create(:family_membership, family: family, user: member)
    auto_user = create(:user, plan: :family, skip_auto_trial: true)
    JobOutbox.delete_all
    clear_enqueued_jobs
    job_owner!('command:families.auto_create', :oban)
    job_owner!('command:families.member_sync', :oban)
    sync_job = Families::MemberSyncJob.new(family.id)
    auto_job = Families::AutoCreationJob.new(auto_user.id)
    Time.use_zone('Asia/Tokyo') do
      I18n.with_locale(:de) do
        expect { 2.times { auto_job.perform(auto_user.id) } }.not_to(change { Family.count })
        expect { 2.times { sync_job.perform(family.id) } }.not_to(change { member.reload.plan })
      end
    end
    expect(JobOutbox.pending.count).to eq(2)
    auto = JobOutbox.pending.find_by!(command_type: 'families.auto_create')
    sync = JobOutbox.pending.find_by!(command_type: 'families.member_sync')
    expect(auto.payload).to eq('user_id' => auto_user.id, 'time_zone' => 'Asia/Tokyo')
    expect(sync.payload).to eq('family_id' => family.id, 'locale' => 'de', 'time_zone' => 'Asia/Tokyo')
    due = 1.hour.from_now.change(usec: 0)
    [auto, sync].each { _1.update!(scheduled_at: due) }
    job_owner!('command:families.auto_create', :sidekiq)
    job_owner!('command:families.member_sync', :sidekiq)
    JobCommands.rehome!('families.auto_create', by: 'a12d2-spec')
    JobCommands.rehome!('families.member_sync', by: 'a12d2-spec')
    expect(JobOutbox.pending.count).to eq(0)
    expect(Families::AutoCreationJob).to have_been_enqueued.with(auto_user.id).at(due)
    expect(Families::MemberSyncJob).to have_been_enqueued.with(family.id).at(due)
    sync_enqueued = enqueued_jobs.find { _1[:job] == Families::MemberSyncJob }
    expect(sync_enqueued.fetch('locale')).to eq('de')
    expect(sync_enqueued.fetch('timezone')).to eq('Asia/Tokyo')
    clear_enqueued_jobs
    Time.use_zone('Asia/Tokyo') do
      I18n.with_locale(:de) do
        auto_job.perform(auto_user.id)
        sync_job.perform(family.id)
      end
    end
    expect(auto_user.reload).to be_in_family
    expect(auto_user.settings.dig('family', 'location_sharing', 'started_at')).to end_with('+09:00')
    expect(member.reload).to be_pro
    expect(JobOutbox.pending.count).to eq(0)
  end
  it 'retains string positional ids and source context when forwarding family jobs' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    auto_user = create(:user, plan: :family, skip_auto_trial: true)
    owner = create(:user, plan: :family, active_until: 1.day.from_now, skip_auto_trial: true)
    family = create(:family, creator: owner)
    member = create(:user, plan: :lite, status: :inactive, skip_auto_trial: true)
    create(:family_membership, family: family, user: member)
    JobOutbox.delete_all
    clear_enqueued_jobs

    Time.use_zone('Asia/Tokyo') do
      I18n.with_locale(:de) do
        Families::AutoCreationJob.new.perform(auto_user.id.to_s)
        Families::MemberSyncJob.new.perform(family.id.to_s)
      end
    end
    expect(auto_user.reload).to be_in_family
    expect(member.reload).to be_pro
    expect(JobOutbox.count).to eq(0)

    job_owner!('command:families.auto_create', :oban)
    job_owner!('command:families.member_sync', :oban)
    Time.use_zone('Asia/Tokyo') do
      I18n.with_locale(:de) do
        Families::AutoCreationJob.new.perform(auto_user.id.to_s)
        Families::MemberSyncJob.new.perform(family.id.to_s)
      end
    end
    expect(JobOutbox.pending.find_by!(command_type: 'families.auto_create').payload)
      .to eq('user_id' => auto_user.id.to_s, 'time_zone' => 'Asia/Tokyo')
    expect(JobOutbox.pending.find_by!(command_type: 'families.member_sync').payload)
      .to eq('family_id' => family.id.to_s, 'locale' => 'de', 'time_zone' => 'Asia/Tokyo')
    expect(enqueued_jobs).to be_empty
  end
  it 'R1 retains integer and numeric string family mail ids through local delivery and forwarding' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(FamilyMailer).to receive(:default).and_return(FamilyMailer.default.merge(from: 'noreply@example.test'))
    owner = create(:user, plan: :family, skip_auto_trial: true)
    family = create(:family, creator: owner)
    member = create(:user, skip_auto_trial: true)
    invitation = create(:family_invitation, family: family, invited_by: owner, status: :pending)
    JobOutbox.delete_all
    ActionMailer::Base.deliveries.clear

    [->(id) { id }, ->(id) { id.to_s }, ->(id) { "+000#{id}" }].each do |form|
      invitation_id, user_id, family_id = [invitation.id, member.id, family.id].map(&form)
      job_owner!('command:mail.family_invitation', :sidekiq)
      job_owner!('command:mail.family_lapse', :sidekiq)
      Families::LapseNotice.clear(member.reload)
      I18n.with_locale(:de) do
        expect do
          Family::Invitations::SendingJob.new.perform(invitation_id)
          Families::LapseNotificationJob.new.perform(user_id, family_id)
        end.to change { ActionMailer::Base.deliveries.size }.by(2)
      end
      expect(ActionMailer::Base.deliveries.last(2).map(&:to)).to eq([[invitation.email], [member.email]])

      job_owner!('command:mail.family_invitation', :oban)
      job_owner!('command:mail.family_lapse', :oban)
      I18n.with_locale(:de) do
        expect do
          Family::Invitations::SendingJob.new.perform(invitation_id)
          Families::LapseNotificationJob.new.perform(user_id, family_id)
        end.not_to(change { ActionMailer::Base.deliveries.size })
      end
      expect(JobOutbox.pending.find_by!(command_type: 'mail.family_invitation').payload)
        .to eq('invitation_id' => invitation_id, 'locale' => 'de')
      expect(JobOutbox.pending.find_by!(command_type: 'mail.family_lapse').payload)
        .to eq('user_id' => user_id, 'family_id' => family_id, 'locale' => 'de', 'lapse_at' => 'none')
      JobOutbox.delete_all
    end

    job_owner!('command:mail.family_invitation', :sidekiq)
    job_owner!('command:mail.family_lapse', :sidekiq)
    [nil, '', 'invalid', '9223372036854775808', '-9223372036854775809'].each do |bad|
      expect do
        Family::Invitations::SendingJob.new.perform(bad)
        Families::LapseNotificationJob.new.perform(bad, family.id)
        Families::LapseNotificationJob.new.perform(member.id, bad)
      end.not_to(change { ActionMailer::Base.deliveries.size })
    end
  end
end
