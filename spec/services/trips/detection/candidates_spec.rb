# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::Detection::Candidates do
  let(:berlin) { ActiveSupport::TimeZone['Europe/Berlin'] }
  let(:t) { ->(*args) { berlin.local(*args) } }

  def run(first_far, last_far, home_before: nil, home_after: nil, closed: true)
    Trips::Detection::AwayPeriods::AwayPeriod.new(first_far, last_far, home_before, home_after, closed)
  end

  def result_for(*runs, zone: berlin) = described_class.new(runs, time_zone: zone).call
  def periods(*runs, zone: berlin) = result_for(*runs, zone:).periods
  def candidate(started_at, ended_at) = described_class::Candidate.new(started_at, ended_at)

  it 'joins the road when the points at home are within 24 hours' do
    result = periods(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11],
                         home_before: t[2026, 10, 10, 8], home_after: t[2026, 10, 14, 20]))
    expect(result).to eq([candidate(t[2026, 10, 10, 8], t[2026, 10, 14, 20])])
  end

  it 'joins the road when the point at home is exactly 24 hours away' do
    result = periods(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11],
                         home_before: t[2026, 10, 9, 16], home_after: t[2026, 10, 15, 11]))
    expect(result).to eq([candidate(t[2026, 10, 9, 16], t[2026, 10, 15, 11])])
  end

  it 'starts and ends at the far points when home is more than 24 hours away' do
    result = periods(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11],
                         home_before: t[2026, 9, 26, 8], home_after: t[2026, 10, 21, 20]))
    expect(result).to eq([candidate(t[2026, 10, 10, 16], t[2026, 10, 14, 11])])
  end

  it 'drops five hours of far points surrounded by silence' do
    expect(periods(run(t[2026, 10, 10, 12], t[2026, 10, 10, 17],
                       home_before: t[2026, 9, 26, 8], home_after: t[2026, 10, 17, 20]))).to be_empty
  end

  it 'needs 03:00 between the first and the last far point' do
    expect(periods(run(t[2026, 10, 10, 18], t[2026, 10, 11, 2, 59]))).to be_empty
    expect(periods(run(t[2026, 10, 10, 18], t[2026, 10, 11, 3, 0])).size).to eq(1)
  end

  it 'tests the night on the far points, not on the joined road' do
    expect(periods(run(t[2026, 10, 10, 4], t[2026, 10, 10, 23],
                       home_before: t[2026, 10, 9, 23], home_after: t[2026, 10, 11, 5]))).to be_empty
  end

  it 'drops a run that is not closed' do
    expect(periods(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11], closed: false))).to be_empty
  end

  it 'skips a run longer than 90 days and reports it' do
    expect(result_for(run(t[2026, 1, 1, 12], t[2026, 4, 2, 12])))
      .to have_attributes(periods: [], long_absence: true)
  end

  it 'keeps a run of exactly 90 days' do
    expect(periods(run(t[2026, 1, 1, 12], t[2026, 4, 1, 12])).size).to eq(1)
  end

  it 'measures 90 days in elapsed time, not calendar days' do
    # 90 days minus 30 minutes across the spring clock change
    expect(periods(run(t[2026, 1, 1, 12], t[2026, 4, 1, 12, 30])).size).to eq(1)
  end

  it 'does not report a long absence for an unfinished run' do
    expect(result_for(run(t[2026, 1, 1, 12], t[2026, 4, 2, 12], closed: false)))
      .to have_attributes(periods: [], long_absence: false)
  end

  it 'does not report a long absence when nothing was skipped' do
    expect(result_for(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11])).long_absence).to be(false)
  end

  # Review Focus 2
  it 'merges overlapping runs from two devices into one period' do
    result = periods(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11]), run(t[2026, 10, 10, 17], t[2026, 10, 14, 13]))
    expect(result).to eq([candidate(t[2026, 10, 10, 16], t[2026, 10, 14, 13])])
  end

  it 'merges runs that only touch' do
    result = periods(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11]), run(t[2026, 10, 14, 11], t[2026, 10, 18, 9]))
    expect(result).to eq([candidate(t[2026, 10, 10, 16], t[2026, 10, 18, 9])])
  end

  it 'keeps the outer end when one run lies inside another' do
    result = periods(run(t[2026, 10, 10, 16], t[2026, 10, 20, 11]), run(t[2026, 10, 12, 17], t[2026, 10, 14, 13]))
    expect(result).to eq([candidate(t[2026, 10, 10, 16], t[2026, 10, 20, 11])])
  end

  it 'merges runs whose joined roads overlap' do
    result = periods(run(t[2026, 10, 10, 16], t[2026, 10, 14, 11], home_after: t[2026, 10, 14, 20]),
                     run(t[2026, 10, 14, 18], t[2026, 10, 16, 9]))
    expect(result).to eq([candidate(t[2026, 10, 10, 16], t[2026, 10, 16, 9])])
  end

  it 'keeps separate runs apart, sorted by start' do
    result = periods(run(t[2026, 10, 20, 16], t[2026, 10, 22, 11]), run(t[2026, 10, 10, 16], t[2026, 10, 12, 11]))
    expect(result).to eq([candidate(t[2026, 10, 10, 16], t[2026, 10, 12, 11]),
                          candidate(t[2026, 10, 20, 16], t[2026, 10, 22, 11])])
  end

  # Review Focus 4
  it 'uses the given zone for the night' do
    utc = ActiveSupport::TimeZone['UTC']
    first = Time.utc(2026, 10, 10, 23) # 01:00 in Berlin
    last = Time.utc(2026, 10, 11, 2)   # 04:00 in Berlin
    expect(periods(run(first, last), zone: utc)).to be_empty
    expect(periods(run(first, last), zone: berlin).size).to eq(1)
  end

  it 'finds the night when the clocks go forward and back' do
    expect(periods(run(t[2026, 3, 28, 20], t[2026, 3, 29, 9])).size).to eq(1)    # 02:00 → 03:00
    expect(periods(run(t[2026, 10, 24, 20], t[2026, 10, 25, 9])).size).to eq(1)  # 03:00 → 02:00
  end
end
