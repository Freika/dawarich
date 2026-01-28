# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::RecalculateDataJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }

    before do
      allow(Stats::CalculateMonth).to receive(:new).and_call_original
      allow_any_instance_of(Stats::CalculateMonth).to receive(:call)

      allow(Tracks::ParallelGenerator).to receive(:new).and_call_original
      allow_any_instance_of(Tracks::ParallelGenerator).to receive(:call)

      allow(Users::Digests::CalculateYear).to receive(:new).and_call_original
      allow_any_instance_of(Users::Digests::CalculateYear).to receive(:call)
    end

    context 'with a specific year' do
      let(:year) { 2024 }

      subject { described_class.perform_now(user.id, year: year) }

      before do
        allow(user).to receive(:years_tracked).and_return([{ year: 2023, months: %w[Jan Feb] },
                                                           { year: 2024, months: %w[Mar Apr] }])
      end

      it 'recalculates stats for all months of the specified year' do
        subject

        (1..12).each do |month|
          expect(Stats::CalculateMonth).to have_received(:new).with(user.id, year, month)
        end
      end

      it 'recalculates tracks for the specified year' do
        subject

        expect(Tracks::ParallelGenerator).to have_received(:new).with(
          user,
          start_at: Time.zone.local(year, 1, 1).beginning_of_day,
          end_at: Time.zone.local(year, 12, 31).end_of_day,
          mode: :bulk
        )
      end

      it 'recalculates digests for the specified year' do
        subject

        expect(Users::Digests::CalculateYear).to have_received(:new).with(user.id, year)
      end

      it 'creates a success notification' do
        expect { subject }.to change { Notification.count }.by(1)
        expect(Notification.last.kind).to eq('info')
        expect(Notification.last.title).to eq('Data recalculation completed')
        expect(Notification.last.content).to include('2024')
      end
    end

    context 'without a specific year (all time)' do
      subject { described_class.perform_now(user.id) }

      before do
        allow_any_instance_of(User).to receive(:years_tracked).and_return([
                                                                            { year: 2023, months: %w[Jan Feb] },
                                                                            { year: 2024, months: %w[Mar Apr] }
                                                                          ])
      end

      it 'recalculates stats for all tracked years' do
        subject

        [2023, 2024].each do |y|
          (1..12).each do |month|
            expect(Stats::CalculateMonth).to have_received(:new).with(user.id, y, month)
          end
        end
      end

      it 'recalculates tracks for all tracked years' do
        subject

        [2023, 2024].each do |y|
          expect(Tracks::ParallelGenerator).to have_received(:new).with(
            user,
            start_at: Time.zone.local(y, 1, 1).beginning_of_day,
            end_at: Time.zone.local(y, 12, 31).end_of_day,
            mode: :bulk
          )
        end
      end

      it 'recalculates digests for all tracked years' do
        subject

        expect(Users::Digests::CalculateYear).to have_received(:new).with(user.id, 2023)
        expect(Users::Digests::CalculateYear).to have_received(:new).with(user.id, 2024)
      end

      it 'creates a success notification mentioning multiple years' do
        expect { subject }.to change { Notification.count }.by(1)
        expect(Notification.last.content).to include('2 years')
      end
    end

    context 'when user has no tracked data' do
      subject { described_class.perform_now(user.id) }

      before do
        allow_any_instance_of(User).to receive(:years_tracked).and_return([])
      end

      it 'does not call any recalculation services' do
        subject

        expect(Stats::CalculateMonth).not_to have_received(:new)
        expect(Tracks::ParallelGenerator).not_to have_received(:new)
        expect(Users::Digests::CalculateYear).not_to have_received(:new)
      end

      it 'does not create a notification' do
        expect { subject }.not_to(change { Notification.count })
      end
    end

    context 'when an error occurs' do
      subject { described_class.perform_now(user.id, year: 2024) }

      before do
        allow_any_instance_of(User).to receive(:years_tracked).and_return([{ year: 2024, months: %w[Jan] }])
        allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_raise(StandardError.new('Test error'))
      end

      it 'creates an error notification' do
        expect do
          subject
        rescue StandardError
          nil
        end.to change { Notification.count }.by(1)
        expect(Notification.last.kind).to eq('error')
        expect(Notification.last.title).to eq('Data recalculation failed')
        expect(Notification.last.content).to include('Test error')
      end

      it 're-raises the error' do
        expect { subject }.to raise_error(StandardError, 'Test error')
      end
    end

    it 'enqueues to the default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end
end
