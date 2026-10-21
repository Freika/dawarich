# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::LoadDisputedAreas do
  def covered?(longitude, latitude)
    DisputedArea.where('ST_Covers(geom, ST_SetSRID(ST_MakePoint(?, ?), 4326))', longitude, latitude).exists?
  end

  before { described_class.new.call }

  it 'covers the bundled disputed areas' do
    expect(covered?(34.10, 44.95)).to be(true) # Simferopol
    expect(covered?(35.69, 32.99)).to be(true) # Katzrin, Golan Heights
    expect(covered?(74.80, 34.08)).to be(true) # Srinagar, Jammu and Kashmir
    expect(covered?(44.06, 9.56)).to be(true) # Hargeisa, Somaliland
  end

  it 'leaves undisputed land and excluded whole territories alone' do
    expect(covered?(30.52, 50.45)).to be(false) # Kyiv
    expect(covered?(121.56, 25.04)).to be(false) # Taipei
    expect(covered?(-57.86, -51.70)).to be(false) # Stanley, Falkland Islands
    expect(covered?(63.31, 45.62)).to be(false) # Baikonur lease
  end

  it 'replaces the previous load instead of duplicating it' do
    expect { described_class.new.call }.not_to(change { DisputedArea.count })
  end
end
