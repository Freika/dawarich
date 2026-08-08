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

  it 'localizes both halves of the suggested-visits notification' do
    allow_any_instance_of(Visits::SmartDetect).to receive(:call).and_return([build(:visit)])

    Visits::Suggest.new(german_user, start_at: 1.day.ago.to_i, end_at: Time.current.to_i).call

    notification = german_user.notifications.last
    expect(notification.title).to eq('Neue Aufenthalte vorgeschlagen')
    expect(notification.content).to include('Zeitleiste')
    expect(notification.content).not_to include('have been suggested')
  end

  it 'localizes the suggested-visits failure notification' do
    allow_any_instance_of(Visits::SmartDetect).to receive(:call).and_raise(StandardError, 'boom')

    Visits::Suggest.new(german_user, start_at: 1.day.ago.to_i, end_at: Time.current.to_i).call

    expect(german_user.notifications.last.title).to eq('Fehler beim Vorschlagen von Aufenthalten')
  end

  it 'leaves the ambient locale untouched after notifying' do
    allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError, 'boom')

    Stats::CalculatingJob.perform_now(german_user.id, 2026, 3)

    expect(I18n.locale).to eq(:en)
  end
end
