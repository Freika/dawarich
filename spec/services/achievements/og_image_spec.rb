# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Achievements::OgImage do
  let(:set) do
    instance_double(
      Achievements::SetPresenter,
      name: 'Germany Explorer', rarity: 'Rare', locked?: false, percent: 6, completed?: false,
      card_attributes: {
        metric_label: '1/16 regions', earned_label: '1/16 regions',
        silhouette: { viewbox: '0 0 100 100', path: 'M10 10 L90 10 L90 90 Z' }
      }
    )
  end

  it 'renders an OG-sized PNG from the achievement card data' do
    png = described_class.new(set).call

    expect(png.b).to start_with("\x89PNG\r\n\x1A\n".b)
    expect(png.byteslice(16, 8).unpack('NN')).to eq([1200, 630])
  end

  it 'escapes user-visible text in the SVG source' do
    allow(set).to receive(:name).and_return('A&B <Explorer>')

    svg = described_class.new(set).svg

    expect(svg).to include('A&amp;B &lt;Explorer&gt;')
    expect(Nokogiri::XML(svg).errors).to be_empty
  end

  it 'terminates a renderer that exceeds its timeout' do
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, 'renderer.pid')
      converter = File.join(dir, 'rsvg-convert')
      File.write(converter, "#!/bin/sh\necho $$ > #{pid_file}\nsleep 30\n")
      File.chmod(0o755, converter)
      stub_const('Achievements::OgImage::CONVERTER', converter)
      stub_const('Achievements::OgImage::RENDER_TIMEOUT', 1)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { described_class.new(set).call }.to raise_error(Timeout::Error)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 3
      expect { Process.kill(0, File.read(pid_file).to_i) }.to raise_error(Errno::ESRCH)
    end
  end
end
