# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Polarsteps step points' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, skip_background_processing: true) }

  def attach_steps(steps)
    import.file.attach(io: StringIO.new(steps.to_json), filename: 'steps.json', content_type: 'application/json')
  end

  it 'imports the detected step array and schedules point-derived processing' do
    path = Rails.root.join('spec/fixtures/files/enhanced_import/polarsteps_steps_array.json')
    attach_steps(JSON.parse(File.read(path)))
    expect(Imports::SourceDetector.new_from_file_header(path).detect_source!).to eq(:polarsteps)

    expect do
      Imports::Create.new(user, import).call
    end.to have_enqueued_job(Tracks::ParallelGeneratorJob)

    expect(import.reload).to be_completed
    expect(import.source).to eq('polarsteps')
    expect(import.points.order(:timestamp).pluck(:timestamp)).to eq([1_735_689_600, 1_735_776_000])
    expect(import.points.order(:timestamp).first.lat).to be_within(0.0001).of(35.6762)
    expect(import.points.order(:timestamp).last.lon).to be_within(0.0001).of(135.7681)
  end

  %w[time timestamp arrived departed start_time end_time].each do |key|
    [1_735_689_600, '1735689600'].each do |value|
      it "accepts an epoch #{value.class} in #{key}" do
        attach_steps([{ 'location' => { 'lat' => 0, 'lng' => 12.5 }, key => value }])

        Polarsteps::Importer.new(import, user.id).call

        point = import.points.sole
        expect(point.timestamp).to eq(1_735_689_600)
        expect(point.lat).to eq(0)
        expect(point.lon).to eq(12.5)
      end
    end
  end

  it 'keeps top-level coordinates when location is not an object' do
    attach_steps([{ 'location' => 'Berlin', 'lat' => 52.5, 'lon' => 13.4, 'arrived' => 1_735_689_600 }])

    Polarsteps::Importer.new(import, user.id).call

    expect(import.points.sole.timestamp).to eq(1_735_689_600)
  end
end
