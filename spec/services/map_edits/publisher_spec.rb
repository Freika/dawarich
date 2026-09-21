# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapEdits::Publisher do
  let(:user) { create(:user) }
  let(:point) { create(:point, user:) }
  let(:result) do
    Points::Move::Result.new(
      point:, track: nil, point_revision: point.lock_version,
      track_revision: nil, visited_countries: nil
    )
  end

  it 'publishes one versioned canonical point_moved event' do
    canonical = { point: { id: point.id }, track: nil, revision: { point: 1, track: nil } }
    allow(MapEdits::Serializer).to receive(:call).with(result).and_return(canonical)

    expect do
      described_class.call(user:, result:)
    end.to have_broadcasted_to(user).from_channel(MapEditsChannel).with(
      type: 'point_moved', version: 1, data: canonical
    )
  end

  it 'reports but does not re-raise a broadcast failure' do
    allow(MapEditsChannel).to receive(:broadcast_to).and_raise('cable unavailable')
    allow(ExceptionReporter).to receive(:call)

    expect do
      described_class.call(user:, result:)
    end.to increment_yabeda_counter(Yabeda.dawarich_map.post_commit_failures_total)
      .with_tags(operation: 'broadcast')
    expect(ExceptionReporter).to have_received(:call).with(
      instance_of(RuntimeError), 'Failed to publish committed map edit'
    )
  end
end
