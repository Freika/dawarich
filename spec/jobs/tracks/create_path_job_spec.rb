# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::CreatePathJob, type: :job do
  let!(:track) { create(:track) }
  let!(:points) { create_list(:point, 3, user: track.user, timestamp: track.started_at.to_i) }
  let(:track_path) do
    "LINESTRING (#{points.map do |point|
      "#{point.longitude.to_f.round(5)} #{point.latitude.to_f.round(5)}"
    end.join(', ')})"
  end

  before do
    track.update(path: nil)
  end

  it 'creates a path for a track' do
    described_class.perform_now(track.id)

    expect(track.reload.path.to_s).to eq(track_path)
  end
end
