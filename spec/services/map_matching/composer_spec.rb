# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::Composer do
  it 'builds an ordered MultiLineString without connecting separate parts' do
    geometry = described_class.call([
                                      [[13.4, 52.5], [13.41, 52.51]],
                                      [[13.5, 52.6], [13.51, 52.61]]
                                    ])

    expect(geometry.geometry_type.type_name).to eq('MultiLineString')
    expect(geometry.num_geometries).to eq(2)
    expect(geometry.geometry_n(0).point_n(0).x).to eq(13.4)
    expect(geometry.geometry_n(1).point_n(0).x).to eq(13.5)
  end
end
