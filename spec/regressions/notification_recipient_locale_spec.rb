# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notification recipient locale' do
  let(:german_user) { create(:user, settings: { 'locale' => 'de' }) }

  it 'localizes a failure notification raised inside a per-user job' do
    allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError, 'boom')

    Stats::CalculatingJob.perform_now(german_user.id, 2026, 3)

    expect(german_user.notifications.last.title).to eq('Statistikupdate fehlgeschlagen')
  end

  it 'localizes per recipient when one job notifies several users' do
    english_user = create(:user)
    [german_user, english_user].each do |user|
      create(:export, user: user, status: :processing)
        .update_column(:processing_started_at, 3.hours.ago)
    end

    StaleJobsRecoveryJob.perform_now

    expect(german_user.notifications.last.title).to eq('Export fehlgeschlagen')
    expect(english_user.notifications.last.title).to eq('Export failed')
  end

  it 'localizes export notifications produced by a service' do
    export = create(:export, user: german_user, status: :processing)
    allow_any_instance_of(Exports::Create).to receive(:build_export_tempfile).and_raise(StandardError, 'boom')

    Exports::Create.new(export: export).call

    expect(german_user.notifications.last.title).to eq('Export fehlgeschlagen')
  end

  it 'leaves the ambient locale untouched after notifying' do
    allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError, 'boom')

    Stats::CalculatingJob.perform_now(german_user.id, 2026, 3)

    expect(I18n.locale).to eq(:en)
  end
end
