# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::FindInTime do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:place) { create(:place) }

  let(:reference_time) { Time.zone.parse('2023-01-15 12:00:00') }

  let!(:visit1) do
    create(
      :visit,
      user: user,
      place: place,
      started_at: reference_time,
      ended_at: reference_time + 1.hour
    )
  end

  let!(:visit2) do
    create(
      :visit,
      user: user,
      place: place,
      started_at: reference_time + 2.hours,
      ended_at: reference_time + 3.hours
    )
  end

  # Visit outside range (before)
  let!(:visit_before) do
    create(
      :visit,
      user: user,
      place: place,
      started_at: reference_time - 3.hours,
      ended_at: reference_time - 2.hours
    )
  end

  # Visit outside range (after)
  let!(:visit_after) do
    create(
      :visit,
      user: user,
      place: place,
      started_at: reference_time + 5.hours,
      ended_at: reference_time + 6.hours
    )
  end

  # Visit for different user within range
  let!(:other_user_visit) do
    create(
      :visit,
      user: other_user,
      place: place,
      started_at: reference_time + 1.hour,
      ended_at: reference_time + 2.hours
    )
  end

  describe '#call' do
    context 'when given a time range' do
      let(:params) do
        {
          start_at: reference_time.to_s,
          end_at: (reference_time + 4.hours).to_s
        }
      end

      subject(:result) { described_class.new(user, params).call }

      it 'returns visits within the time range' do
        expect(result).to include(visit1, visit2)
        expect(result).not_to include(visit_before, visit_after)
      end

      it 'returns visits in descending order by started_at' do
        expect(result.to_a).to eq([visit2, visit1])
      end

      it 'does not include visits from other users' do
        expect(result).not_to include(other_user_visit)
      end

      it 'preloads the place association' do
        expect(result.first.association(:place)).to be_loaded
      end
    end

    context 'with visits at the boundaries of the time range' do
      let!(:visit_at_start) do
        create(
          :visit,
          user: user,
          place: place,
          started_at: reference_time,
          ended_at: reference_time + 30.minutes
        )
      end

      let!(:visit_at_end) do
        create(
          :visit,
          user: user,
          place: place,
          started_at: reference_time + 3.hours + 30.minutes,
          ended_at: reference_time + 4.hours
        )
      end

      let(:params) do
        {
          start_at: reference_time.to_s,
          end_at: (reference_time + 4.hours).to_s
        }
      end

      subject(:result) { described_class.new(user, params).call }

      it 'includes visits at the boundaries of the time range' do
        expect(result).to include(visit_at_start, visit_at_end)
      end
    end

    context 'when time parameters are invalid' do
      let(:params) do
        {
          start_at: 'invalid-date',
          end_at: (reference_time + 4.hours).to_s
        }
      end

      it 'raises an ArgumentError' do
        expect { described_class.new(user, params).call }.to raise_error(ArgumentError)
      end
    end
  end
end
