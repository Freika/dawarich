# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit boundary snapping across separate locations' do
  let(:policy) do
    Visits::Detection::Policy.new(
      stay_radius_m: 100, min_dwell_s: 300, min_points: 3, merge_gap_s: 900
    )
  end
  let(:assembler) { Visits::Detection::StayAssembler.new(policy) }
  let(:points) do
    # Invented clusters in the open South Pacific, away from inhabited places.
    [-40.0, -40.01].each_with_index.flat_map do |lat, cluster|
      Array.new(4) do |i|
        Visits::Detection::CandidateLoader::Pt.new(
          cluster * 4 + i + 1, lat, -140.0 + i * 0.0002, 1000 + cluster * 100 + i * 2, 4
        )
      end
    end
  end
  let(:fragments) { Visits::Detection::DwellSweep.new(policy).call(points) }
  let(:bridged) { Visits::Detection::GapBridger.new(policy).call(fragments) }

  def accepted_stays(segments)
    reconciled = Visits::Detection::MovementReconciler.new(policy).call(bridged, segments)
    assembler.call(reconciled, points.index_by(&:id))
  end

  it 'does not expand separate short fragments into simultaneous accepted stays' do
    segments = [
      Visits::Detection::CandidateLoader::Seg.new('driving', 0.9, false, 800, 900),
      Visits::Detection::CandidateLoader::Seg.new('driving', 0.9, false, 1840, 2000)
    ]

    expect(fragments.map { |f| f[:end_ts] - f[:start_ts] }).to eq([6, 6])
    expect(bridged.map { |f| f[:point_ids] }).to eq([[1, 2, 3, 4], [5, 6, 7, 8]])
    expect(assembler.call(bridged, points.index_by(&:id))).to be_empty

    stays = accepted_stays(segments)
    overlaps = stays.combination(2).map do |a, b|
      [a[:end_ts], b[:end_ts]].min - [a[:start_ts], b[:start_ts]].max
    end

    expect(overlaps).to all(be <= 0),
                        "Separate locations must not overlap; accepted intervals: #{stays.map do |s|
                          [s[:start_ts], s[:end_ts]]
                        end}"
  end

  it 'still stretches a lone short stop to the movement around it' do
    lone = points.first(4)
    lone_fragments = Visits::Detection::GapBridger.new(policy).call(Visits::Detection::DwellSweep.new(policy).call(lone))
    segments = [
      Visits::Detection::CandidateLoader::Seg.new('driving', 0.9, false, 800, 900),
      Visits::Detection::CandidateLoader::Seg.new('driving', 0.9, false, 1400, 1500)
    ]
    reconciled = Visits::Detection::MovementReconciler.new(policy).call(lone_fragments, segments)

    expect(assembler.call(reconciled, lone.index_by(&:id)).map { |s| [s[:start_ts], s[:end_ts]] })
      .to eq([[900, 1400]])
  end

  it 'rejects the short fragments when there are no movement boundaries' do
    expect(accepted_stays([])).to be_empty
  end

  context 'with enough stationary evidence' do
    let(:points) do
      Array.new(4) do |i|
        Visits::Detection::CandidateLoader::Pt.new(i + 1, -40.0, -140.0, 1000 + i * 300, 4)
      end
    end

    it 'accepts a stationary stay supported by 900 seconds of fixes' do
      expect(accepted_stays([]).map { |s| [s[:start_ts], s[:end_ts], s[:duration_s], s[:point_ids]] })
        .to eq([[1000, 1900, 900, [1, 2, 3, 4]]])
    end
  end
end
