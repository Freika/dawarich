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
end
