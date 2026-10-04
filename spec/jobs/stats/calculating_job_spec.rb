# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::CalculatingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }

    subject { described_class.perform_now(user.id, 2024, 1) }

    before do
      allow(Stats::CalculateMonth).to receive(:new).and_call_original
      allow_any_instance_of(Stats::CalculateMonth).to receive(:call)
    end

    it 'calls Stats::CalculateMonth service' do
      subject

      expect(Stats::CalculateMonth).to have_received(:new).with(user.id, 2024, 1, notify_on_failure: true)
    end

    context 'when Stats::CalculateMonth raises an error' do
      before do
        allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_raise(StandardError)
      end

      it 'creates an error notification' do
        expect { subject }.to change { Notification.count }.by(1)
        expect(Notification.last.kind).to eq('error')
      end

      it 'creates the notification in the user saved locale' do
        user.update!(settings: { 'locale' => 'fr' })

        I18n.with_locale(:en) { subject }

        expect(user.notifications.last.title).to eq('Échec de la mise à jour des statistiques')
      end
    end

    context 'when Stats::CalculateMonth handles an internal error' do
      before do
        user.update!(settings: { 'locale' => 'fr' })
        allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_call_original
        allow_any_instance_of(Stats::CalculateMonth).to receive(:points).and_raise(StandardError, 'boom')
      end

      it 'creates the service notification in the user saved locale' do
        I18n.with_locale(:en) { subject }

        expect(user.notifications.last.title).to eq("L'actualisation des statistiques a échoué")
        expect(user.notifications.last.content).to include('boom')
      end
    end

    it 'Oban-owned: forwards the month with integer year and month and calculates nothing' do
      job_owner!(described_class::OWNER_KEY, :oban)
      job = described_class.new(user.id, '2024', '3', notify_on_failure: false)

      job.perform_now

      expect(JobOutbox.sole).to have_attributes(
        command_type: 'stats.calculate_month', aggregate_id: user.id, event_id: job.job_id,
        payload: { 'user_id' => user.id, 'year' => 2024, 'month' => 3, 'notify_on_failure' => false }
      )
      expect(Stats::CalculateMonth).not_to have_received(:new)
    end

    it 'Oban-owned: a failing forward raises for a Sidekiq retry and notifies nobody' do
      job_owner!(described_class::OWNER_KEY, :oban)
      allow(JobCommands).to receive(:forward).and_raise(ActiveRecord::ConnectionNotEstablished, 'down')

      expect do
        expect { described_class.perform_now(user.id, 2024, 1) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end.not_to change(Notification, :count)
    end
  end
end
