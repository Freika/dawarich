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

    context 'when stats already exist' do
      let(:user) { create(:user) }

      subject { described_class.new(user.id) }

      let!(:old_point) do
        create(:point, user: user, timestamp: DateTime.new(2020, 6, 15, 12, 0, 0).to_i)
      end

      let!(:new_point) do
        create(:point, user: user, timestamp: DateTime.new(2021, 3, 10, 12, 0, 0).to_i)
      end

      before do
        create(:stat, user: user, year: 2020, month: 6, updated_at: DateTime.new(2020, 7, 1))
      end

      it 'only schedules calculations for months with points after last calculation' do
        subject.call

        expect(Stats::CalculatingJob).not_to have_been_enqueued.with(user.id, 2020, 6)
        expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2021, 3)
      end
    end

    context 'with points spanning multiple months' do
      let(:user) { create(:user) }

      subject { described_class.new(user.id) }

      let!(:jan_point) do
        create(:point, user: user, timestamp: DateTime.new(2021, 1, 15, 12, 0, 0).to_i)
      end

      let!(:mar_point) do
        create(:point, user: user, timestamp: DateTime.new(2021, 3, 10, 12, 0, 0).to_i)
      end

      let!(:mar_point2) do
        create(:point, user: user, timestamp: DateTime.new(2021, 3, 20, 12, 0, 0).to_i)
      end

      it 'schedules one job per distinct month' do
        subject.call

        expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2021, 1).once
        expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2021, 3).once
        expect(Stats::CalculatingJob).to have_been_enqueued.exactly(2).times
      end
    end
  end
end
