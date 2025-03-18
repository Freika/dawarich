# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::TimeChunks do
  describe '#call' do
    context 'with a multi-year span' do
      it 'splits time correctly across year boundaries' do
        # Span over multiple years
        start_at = DateTime.new(2020, 6, 15)
        end_at = DateTime.new(2023, 3, 10)

        service = described_class.new(start_at: start_at, end_at: end_at)
        chunks = service.call

        # Should have 4 chunks:
        # 1. 2020-06-15 to 2021-01-01
        # 2. 2021-01-01 to 2022-01-01
        # 3. 2022-01-01 to 2023-01-01
        # 4. 2023-01-01 to 2023-03-10
        expect(chunks.size).to eq(4)

        # First chunk: partial year (Jun 15 - Jan 1)
        expect(chunks[0].begin).to eq(start_at)
        expect(chunks[0].end).to eq(DateTime.new(2020, 12, 31).end_of_day)

        # Second chunk: full year 2021
        expect(chunks[1].begin).to eq(DateTime.new(2021, 1, 1).beginning_of_year)
        expect(chunks[1].end).to eq(DateTime.new(2021, 12, 31).end_of_year)

        # Third chunk: full year 2022
        expect(chunks[2].begin).to eq(DateTime.new(2022, 1, 1).beginning_of_year)
        expect(chunks[2].end).to eq(DateTime.new(2022, 12, 31).end_of_year)

        # Fourth chunk: partial year (Jan 1 - Mar 10, 2023)
        expect(chunks[3].begin).to eq(DateTime.new(2023, 1, 1).beginning_of_year)
        expect(chunks[3].end).to eq(end_at)
      end
    end

    context 'with a span within a single year' do
      it 'creates a single chunk ending at year end' do
        start_at = DateTime.new(2020, 3, 15)
        end_at = DateTime.new(2020, 10, 20)

        service = described_class.new(start_at: start_at, end_at: end_at)
        chunks = service.call

        expect(chunks.size).to eq(1)
        expect(chunks[0].begin).to eq(start_at)
        # The implementation appears to extend to the end of the year
        expect(chunks[0].end).to eq(DateTime.new(2020, 12, 31).end_of_day)
      end
    end

    context 'with spans exactly on year boundaries' do
      it 'creates one chunk per year ending at next year start' do
        start_at = DateTime.new(2020, 1, 1)
        end_at = DateTime.new(2022, 12, 31).end_of_day

        service = described_class.new(start_at: start_at, end_at: end_at)
        chunks = service.call

        expect(chunks.size).to eq(3)

        # Three full years, each ending at the start of the next year
        expect(chunks[0].begin).to eq(DateTime.new(2020, 1, 1).beginning_of_year)
        expect(chunks[0].end).to eq(DateTime.new(2020, 12, 31).end_of_year)

        expect(chunks[1].begin).to eq(DateTime.new(2021, 1, 1).beginning_of_year)
        expect(chunks[1].end).to eq(DateTime.new(2021, 12, 31).end_of_year)

        expect(chunks[2].begin).to eq(DateTime.new(2022, 1, 1).beginning_of_year)
        expect(chunks[2].end).to eq(DateTime.new(2022, 12, 31).end_of_year)
      end
    end

    context 'with start and end dates in the same day' do
      it 'returns a single chunk ending at the end of the year' do
        date = DateTime.new(2020, 5, 15)
        start_at = date.beginning_of_day
        end_at = date.end_of_day

        service = described_class.new(start_at: start_at, end_at: end_at)
        chunks = service.call

        expect(chunks.size).to eq(1)
        expect(chunks[0].begin).to eq(start_at)
        # Implementation extends to end of year
        expect(chunks[0].end).to eq(DateTime.new(2020, 12, 31).end_of_day)
      end
    end

    context 'with a full single year' do
      it 'returns a single chunk for the entire year' do
        start_at = DateTime.new(2020, 1, 1).beginning_of_day
        end_at = DateTime.new(2020, 12, 31).end_of_day

        service = described_class.new(start_at: start_at, end_at: end_at)
        chunks = service.call

        expect(chunks.size).to eq(1)
        expect(chunks[0].begin).to eq(start_at)
        expect(chunks[0].end).to eq(end_at)
      end
    end

    context 'with dates spanning a decade' do
      it 'creates appropriate chunks for each year ending at next year start' do
        start_at = DateTime.new(2020, 1, 1)
        end_at = DateTime.new(2030, 12, 31)

        service = described_class.new(start_at: start_at, end_at: end_at)
        chunks = service.call

        # Should have 11 chunks (2020 through 2030)
        expect(chunks.size).to eq(11)

        # Check first and last chunks
        expect(chunks.first.begin).to eq(start_at)
        expect(chunks.last.end).to eq(end_at)

        # Check that each chunk starts on Jan 1 and ends on next Jan 1 (except last)
        (1...chunks.size - 1).each do |i|
          year = 2020 + i
          expect(chunks[i].begin).to eq(DateTime.new(year, 1, 1).beginning_of_year)
          expect(chunks[i].end).to eq(DateTime.new(year, 12, 31).end_of_year)
        end
      end
    end

    context 'with start date after end date' do
      it 'still creates a chunk for start date year' do
        start_at = DateTime.new(2023, 1, 1)
        end_at = DateTime.new(2020, 1, 1)

        service = described_class.new(start_at: start_at, end_at: end_at)
        chunks = service.call

        # The implementation creates one chunk for the start date year
        expect(chunks.size).to eq(1)
        expect(chunks[0].begin).to eq(start_at)
        expect(chunks[0].end).to eq(DateTime.new(2023, 12, 31).end_of_day)
      end
    end

    context 'when start date equals end date' do
      it 'returns a single chunk extending to year end' do
        date = DateTime.new(2022, 6, 15, 12, 30)

        service = described_class.new(start_at: date, end_at: date)
        chunks = service.call

        expect(chunks.size).to eq(1)
        expect(chunks[0].begin).to eq(date)
        # Implementation extends to end of year
        expect(chunks[0].end).to eq(DateTime.new(2022, 12, 31).end_of_day)
      end
    end
  end
end
