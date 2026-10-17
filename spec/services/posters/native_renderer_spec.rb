# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::NativeRenderer do
  let(:poster) { create(:poster, settings: settings) }
  let(:settings) do
    {
      'lat' => 52.49, 'lon' => 13.39, 'distance' => 15_000,
      'theme' => 'autumn',
      'start_at' => '2025-10-01T00:00:00Z', 'end_at' => '2025-10-31T23:59:59Z'
    }
  end
  let(:track) do
    { 'type' => 'MultiLineString', 'coordinates' => [[[13.28, 52.44], [13.5, 52.51]]] }
  end
  let(:fake_command) { ['ruby', Rails.root.join('spec/fixtures/scripts/fake_poster_renderer.rb').to_s] }

  def build_renderer(command: fake_command)
    described_class.new(
      poster: poster,
      track: track,
      distance: 15_000,
      route_opacity: 0.6,
      subtitle: '1 Oct 2025 – 31 Oct 2025',
      command: command
    )
  end

  def wait_for_renderer_readiness
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args, &render|
      original.call(*args) do |stdin, stdout, stderr, wait_thread|
        ready = JSON.parse(stdout.gets)
        expect(ready.fetch('pid')).to eq(wait_thread.pid)
        expect(ready.fetch('pgrp')).to eq(wait_thread.pid)
        expect(ready.fetch('child')).to be_positive
        yield ready if block_given?
        render.call(stdin, stdout, stderr, wait_thread)
      end
    end
  end

  describe '#call' do
    it 'renders a job carrying theme tokens, track, view, and text' do
      result = build_renderer.call
      job = JSON.parse(result[:png])

      expect(job['tokens']['name']).to eq('Autumn')
      expect(job['trackGeojson']['geometry']['type']).to eq('MultiLineString')
      expect(job['view']).to include('lat' => 52.49, 'lon' => 13.39, 'distance' => 15_000)
      expect(job['trackOpacity']).to eq(0.6)
      expect(job['text']).to include('title' => 'Berlin', 'subtitle' => '1 Oct 2025 – 31 Oct 2025')
      expect(job['output']).to include('widthMm' => 300, 'heightMm' => 400)
      expect(result[:pdf]).to eq('PDF:Berlin')
    end

    it 'carries the track width multiplier into the job' do
      job = JSON.parse(
        described_class.new(
          poster: poster, track: track, distance: 15_000, route_opacity: 0.6,
          route_width: 2.5, subtitle: '1 Oct 2025 – 31 Oct 2025', command: fake_command
        ).call[:png]
      )

      expect(job['trackWidth']).to eq(2.5)
    end

    it 'defaults the track width multiplier to 1' do
      job = JSON.parse(build_renderer.call[:png])

      expect(job['trackWidth']).to eq(1)
    end

    it 'renders the explicit settings title when present' do
      poster.settings['title'] = 'My Trip'

      job = JSON.parse(build_renderer.call[:png])

      expect(job['text']['title']).to eq('My Trip')
    end

    it 'renders a blank title when the settings title is blank (untitled poster)' do
      poster.update!(name: 'Untitled poster', settings: poster.settings.merge('title' => ''))

      job = JSON.parse(build_renderer.call[:png])

      expect(job['text']['title']).to eq('')
    end

    it 'raises when the renderer process fails' do
      renderer = build_renderer(command: ['ruby', '-e', 'warn "boom"; exit 1'])

      expect { renderer.call }.to raise_error(described_class::Error, /boom/)
    end

    it 'terminates a renderer that exceeds the timeout' do
      stub_const("#{described_class}::RENDER_TIMEOUT", 0.05)
      renderer = build_renderer(command: ['ruby', '-e', 'sleep 0.3'])

      expect { renderer.call }.to raise_error(described_class::Error, /timed out after 0.05 seconds/)
    end

    it 'times out when the process leader exits but a descendant retains its pipes' do
      stub_const("#{described_class}::RENDER_TIMEOUT", 0.2)
      stub_const("#{described_class}::TERMINATE_TIMEOUT", 0.05)
      wait_for_renderer_readiness
      command = fake_command + ['exit-parent']

      expect { build_renderer(command:).call }
        .to raise_error(described_class::Error, /timed out after 0.2 seconds/)
    end

    it 'kills TERM-resistant descendants after a renderer timeout' do
      stub_const("#{described_class}::RENDER_TIMEOUT", 0.2)
      stub_const("#{described_class}::TERMINATE_TIMEOUT", 0.05)
      child_pid = nil
      wait_for_renderer_readiness { |ready| child_pid = ready.fetch('child') }
      command = fake_command + ['linger']

      expect { build_renderer(command:).call }
        .to raise_error(described_class::Error, /timed out after 0.2 seconds/)

      child_running = lambda do
        state = IO.popen(['ps', '-o', 'stat=', '-p', child_pid.to_s], &:read).strip
        state.present? && !state.start_with?('Z')
      end
      expect(child_running.call).to be(false)
    ensure
      Process.kill('KILL', child_pid) if child_pid&.positive? && child_running&.call
    end

    it 'does not escalate to KILL when the process group probe returns EPERM' do
      stub_const("#{described_class}::RENDER_TIMEOUT", 0.05)
      process_group_id = nil
      kill_calls = []
      allow(Process).to receive(:kill).and_wrap_original do |original, signal, pid|
        process_group_id ||= pid.abs if signal == 'TERM' && pid.negative?
        kill_calls << [signal, pid]
        raise Errno::EPERM if signal == 0 && pid == -process_group_id

        original.call(signal, pid)
      end
      renderer = build_renderer(command: ['ruby', '-e', 'sleep 0.3'])

      expect { renderer.call }.to raise_error(described_class::Error, /timed out after 0.05 seconds/)
      expect(kill_calls).not_to include(['KILL', -process_group_id])
    end

    it 'raises the timeout error when TERM returns EPERM' do
      stub_const("#{described_class}::RENDER_TIMEOUT", 0.05)
      allow(Process).to receive(:kill).and_wrap_original do |original, signal, pid|
        raise Errno::EPERM if signal == 'TERM' && pid.negative?

        original.call(signal, pid)
      end
      renderer = build_renderer(command: ['ruby', '-e', 'sleep 0.3'])

      expect { renderer.call }.to raise_error(described_class::Error, /timed out after 0.05 seconds/)
    end

    it 'raises when the theme tokens are unknown' do
      poster.settings['theme'] = 'nonexistent_theme'

      expect { build_renderer.call }.to raise_error(described_class::Error, /theme/i)
    end
  end
end
