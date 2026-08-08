# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSegments::DisplayLegs do
  let(:t0) { Time.zone.parse('2026-01-10 10:00:00') }

  def seg(mode, offset_s, duration_s, distance_m, conf: 0.9, corrected: false)
    build_stubbed(:track_segment,
                  transportation_mode: mode,
                  start_at: t0 + offset_s,
                  end_at: t0 + offset_s + duration_s,
                  duration: duration_s,
                  distance: distance_m,
                  confidence_score: conf,
                  corrected_at: corrected ? t0 : nil)
  end

  it 'returns nil when any segment lacks time anchoring' do
    legacy = build_stubbed(:track_segment, start_at: nil, end_at: nil)
    expect(described_class.call([legacy])).to be_nil
  end

  describe 'segment identity' do
    it 'carries the segment id on a leg that maps to exactly one segment' do
      segment = seg(:walking, 0, 600, 800)

      expect(described_class.call([segment]).items.first.segment_id).to eq(segment.id)
    end

    it 'carries the segment id on an unclaimed-mode leg so its mode can be set in place' do
      segment = seg(:unknown, 0, 300, 50, conf: 0.0)
      item = described_class.call([segment]).items.first

      expect(item.kind).to eq(:uncertain)
      expect(item.segment_id).to eq(segment.id)
    end

    it 'leaves a merged transfer without an id — it is more than one segment' do
      segments = [seg(:walking, 0, 60, 30), seg(:walking, 70, 60, 30), seg(:driving, 200, 900, 5000)]
      items = described_class.call(segments).items
      transfer = items.find { |i| i.kind == :transfer }

      expect(transfer).not_to be_nil
      expect(transfer.segment_id).to be_nil
    end

    it 'leaves an inferred stop without an id — no segment underlies it' do
      segments = [seg(:walking, 0, 600, 800), seg(:walking, 1800, 600, 800)]
      stop = described_class.call(segments).items.find { |i| i.kind == :stop }

      expect(stop).not_to be_nil
      expect(stop.segment_id).to be_nil
    end
  end

  it 'returns nil when every segment is stationary' do
    expect(described_class.call([seg(:stationary, 0, 600, 20)])).to be_nil
  end

  it 'drops stationary segments and marks long dwells as stops' do
    segments = [seg(:walking, 0, 600, 800),
                seg(:stationary, 600, 600, 30),
                seg(:driving, 1200, 1800, 20_000)]
    items = described_class.call(segments).items

    expect(items.map(&:kind)).to eq(%i[leg stop leg])
    expect(items[0].mode).to eq('walking')
    expect(items[1].duration).to eq(600)
    expect(items[2].mode).to eq('driving')
  end

  it 'does not insert a stop for gaps shorter than the threshold' do
    segments = [seg(:walking, 0, 600, 800), seg(:driving, 660, 1200, 15_000)]
    expect(described_class.call(segments).items.map(&:kind)).to eq(%i[leg leg])
  end

  it 'merges runs of consecutive short segments into a transfer chip' do
    segments = [seg(:driving, 0, 3600, 50_000),
                seg(:cycling, 3600, 200, 900),
                seg(:walking, 3820, 130, 100),
                seg(:driving, 3960, 140, 350),
                seg(:walking, 4110, 600, 110)]
    items = described_class.call(segments).items

    expect(items.map(&:kind)).to eq(%i[leg transfer leg])
    transfer = items[1]
    expect(transfer.segment_count).to eq(3)
    expect(transfer.distance).to eq(900 + 100 + 350)
    expect(transfer.duration).to eq(4100 - 3600)
  end

  it 'keeps an isolated short segment as a normal leg' do
    segments = [seg(:walking, 0, 180, 150), seg(:driving, 200, 3600, 40_000)]
    items = described_class.call(segments).items

    expect(items.map(&:kind)).to eq(%i[leg leg])
    expect(items[0].mode).to eq('walking')
  end

  it 'shows low-confidence segments as uncertain movement without a mode claim' do
    segments = [seg(:walking, 0, 600, 800), seg(:cycling, 780, 400, 400, conf: 0.42)]
    items = described_class.call(segments).items

    expect(items.map(&:kind)).to eq(%i[leg uncertain])
    expect(items[1].mode).to be_nil
    expect(items[1].distance).to eq(400)
  end

  it 'treats unknown-mode segments as uncertain' do
    items = described_class.call([seg(:unknown, 0, 300, 50, conf: 0.0)]).items
    expect(items.map(&:kind)).to eq([:uncertain])
  end

  it 'never gates or merges manually corrected segments' do
    segments = [seg(:driving, 0, 3600, 50_000),
                seg(:cycling, 3600, 120, 400, conf: 0.3, corrected: true),
                seg(:walking, 3730, 100, 90)]
    items = described_class.call(segments).items

    expect(items.map(&:kind)).to eq(%i[leg leg leg])
    expect(items[1].mode).to eq('cycling')
  end

  it 'builds time-proportional ribbon spans including gaps' do
    segments = [seg(:walking, 0, 600, 800), seg(:driving, 1200, 1200, 15_000)]
    spans = described_class.call(segments).spans

    expect(spans.map(&:kind)).to eq(%i[mode gap mode])
    expect(spans[0].percent).to be_within(0.1).of(25.0)
    expect(spans[1].percent).to be_within(0.1).of(25.0)
    expect(spans[2].percent).to be_within(0.1).of(50.0)
    expect(spans[0].mode).to eq('walking')
  end

  it 'marks uncertain stretches in the ribbon' do
    segments = [seg(:walking, 0, 600, 800), seg(:cycling, 600, 600, 400, conf: 0.4)]
    spans = described_class.call(segments).spans

    expect(spans.map(&:kind)).to eq(%i[mode uncertain])
  end
end
