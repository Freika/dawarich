# frozen_string_literal: true

require 'rails_helper'

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
end
