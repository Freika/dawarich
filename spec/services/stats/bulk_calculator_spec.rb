# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::BulkCalculator do
  describe '#call' do
    context 'with month boundary and timezone' do
      let(:user) { create(:user, settings: user_settings) }

      # Point at Dec 31, 2020 23:30 UTC
      let!(:point) do
        create(:point, user: user, timestamp: DateTime.new(2020, 12, 31, 23, 30, 0).to_i)
      end

      context 'with Etc/UTC timezone' do
        let(:user_settings) { { 'timezone' => 'Etc/UTC' } }

        it 'schedules December 2020 calculation' do
          expect { subject.call }.to have_enqueued_job(Stats::CalculatingJob)
            .with(user.id, 2020, 12)
        end
      end

      context 'with Asia/Tokyo timezone (+9, 23:30 UTC → 08:30 Jan 1)' do
        let(:user_settings) { { 'timezone' => 'Asia/Tokyo' } }

        it 'schedules January 2021 calculation' do
          expect { subject.call }.to have_enqueued_job(Stats::CalculatingJob)
            .with(user.id, 2021, 1)
        end
      end

      subject { described_class.new(user.id) }
    end

    context 'with no points' do
      let(:user) { create(:user) }

      subject { described_class.new(user.id) }

      it 'does not schedule any jobs' do
        expect { subject.call }.not_to have_enqueued_job(Stats::CalculatingJob)
      end
    end
  end
end
