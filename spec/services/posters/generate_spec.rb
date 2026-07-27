# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::Generate do
  let(:poster) { create(:poster) }
  let(:track) { { 'type' => 'MultiLineString', 'coordinates' => [[[13.40, 52.51], [13.41, 52.52]]] } }
  let(:renderer) { instance_double(Posters::NativeRenderer, call: { png: 'png-bytes', pdf: 'pdf-bytes' }) }

  before { allow(Posters::NativeRenderer).to receive(:new).and_return(renderer) }

  def run_generate
    described_class.new(poster).call
  end

  context 'when the render succeeds' do
    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track) }

    it 'attaches the image and completes the poster' do
      run_generate

      expect(poster.reload).to be_completed
      expect(poster.image).to be_attached
      expect(poster.image.download).to eq('png-bytes')
    end

    it 'attaches a print-ready PDF' do
      run_generate

      expect(poster.reload.print_pdf).to be_attached
      expect(poster.print_pdf.content_type).to eq('application/pdf')
      expect(poster.print_pdf.filename.to_s).to end_with('.pdf')
    end

    it 'renders with the poster distance, opacity, subtitle and track' do
      expect(Posters::NativeRenderer).to receive(:new).with(
        poster: poster, track: track, distance: 6000, route_opacity: 1.0, route_width: 1.0,
        subtitle: '1 Apr 2026 – 30 Apr 2026'
      ).and_return(renderer)

      run_generate
    end

    it 'records a render phase on the poster' do
      run_generate

      expect(poster.reload.settings['progress_phase']).to eq('drawing_map')
    end
  end

  context 'when settings request a percentage opacity' do
    let(:poster) do
      create(:poster, settings: attributes_for(:poster)[:settings].merge('route_opacity' => '40'))
    end

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track) }

    it 'passes the opacity as a 0-1 decimal' do
      expect(Posters::NativeRenderer).to receive(:new).with(hash_including(route_opacity: 0.4)).and_return(renderer)

      run_generate
    end
  end

  context 'when settings request a percentage track width' do
    let(:poster) do
      create(:poster, settings: attributes_for(:poster)[:settings].merge('route_width' => '250'))
    end

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track) }

    it 'passes the width as a multiplier' do
      expect(Posters::NativeRenderer).to receive(:new).with(hash_including(route_width: 2.5)).and_return(renderer)

      run_generate
    end
  end

  context 'when settings omit the track width' do
    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track) }

    it 'falls back to the unscaled width' do
      expect(Posters::NativeRenderer).to receive(:new).with(hash_including(route_width: 1.0)).and_return(renderer)

      run_generate
    end
  end

  context 'when settings request a track width beyond the slider range' do
    let(:poster) do
      create(:poster, settings: attributes_for(:poster)[:settings].merge('route_width' => '900'))
    end

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track) }

    it 'clamps the width to the maximum multiplier' do
      expect(Posters::NativeRenderer).to receive(:new).with(hash_including(route_width: 3.0)).and_return(renderer)

      run_generate
    end
  end

  context 'when the requested distance fits within the poster studio range' do
    let(:poster) { create(:poster, settings: attributes_for(:poster)[:settings].merge('distance' => 2_924_948)) }

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track) }

    it 'renders with the requested distance' do
      expect(Posters::NativeRenderer).to receive(:new).with(hash_including(distance: 2_924_948)).and_return(renderer)

      run_generate
    end
  end

  context 'when the requested distance exceeds the poster studio limit' do
    let(:poster) { create(:poster, settings: attributes_for(:poster)[:settings].merge('distance' => 6_000_000)) }

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track) }

    it 'clamps the distance to 5,000km' do
      expect(Posters::NativeRenderer).to receive(:new).with(hash_including(distance: 5_000_000)).and_return(renderer)

      run_generate
    end
  end

  context 'when a continent-wide frame is saved to the gallery' do
    let(:poster) do
      create(:poster, settings: attributes_for(:poster)[:settings].merge(
        'lat' => '40.019826138511576', 'lon' => '17.87175149999996', 'distance' => '2924948'
      ))
    end
    let(:track_through_rome) { { 'type' => 'MultiLineString', 'coordinates' => [[[12.49, 41.90], [12.50, 41.91]]] } }

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track_through_rome) }

    it 'completes instead of reporting the track as outside the map area' do
      run_generate

      expect(poster.reload).to be_completed
      expect(poster.settings['error']).to be_nil
    end
  end

  context 'when there are no points in range' do
    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(nil) }

    it 'fails with a user-facing error and never renders' do
      expect(Posters::NativeRenderer).not_to receive(:new)

      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/No location data/)
    end
  end

  context 'when the native renderer errors' do
    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      allow(Posters::NativeRenderer).to receive(:new).and_raise(Posters::NativeRenderer::Error, 'render exploded')
    end

    it 'fails the poster with a generic error' do
      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to be_present
    end
  end

  context 'when the track is outside the cropped poster area but within the raw distance' do
    let(:nearby_track) { { 'type' => 'MultiLineString', 'coordinates' => [[[13.405, 52.55], [13.406, 52.551]]] } }

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(nearby_track) }

    it 'fails with an area mismatch error and never renders' do
      expect(Posters::NativeRenderer).not_to receive(:new)

      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/does not pass through/)
    end
  end

  context 'when the track does not pass through the poster area' do
    let(:distant_track) { { 'type' => 'MultiLineString', 'coordinates' => [[[14.42, 50.08], [14.43, 50.09]]] } }

    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(distant_track) }

    it 'fails with an area mismatch error and never renders' do
      expect(Posters::NativeRenderer).not_to receive(:new)

      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/does not pass through/)
    end
  end

  context 'when the poster is already completed' do
    let(:poster) { create(:poster, status: :completed) }

    it 'stays completed and never renders' do
      expect(Posters::NativeRenderer).not_to receive(:new)

      run_generate

      expect(poster.reload).to be_completed
    end
  end

  context "when settings include source: 'tracks'" do
    let(:poster) { create(:poster, settings: attributes_for(:poster)[:settings].merge('source' => 'tracks')) }

    before { allow_any_instance_of(Posters::TracksBuilder).to receive(:call).and_return(track) }

    it 'builds the route from tracks and completes the poster' do
      expect(Posters::NativeRenderer).to receive(:new).with(hash_including(track: track)).and_return(renderer)

      run_generate

      expect(poster.reload).to be_completed
    end
  end
end
