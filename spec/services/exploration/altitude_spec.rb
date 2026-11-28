# frozen_string_literal: true

require 'rails_helper'
RSpec.describe 'Exploration flight altitude evidence' do
  it 'supports sustained fast high-altitude travel, not mountain ground movement' do
    flight = { altitude_p50: 4000, speed_p50: 300, stop_fraction: 0 }
    expect(TransportationModes::Emissions.altitude_support(:flying, flight)).to eq(2)
    expect(TransportationModes::Emissions.altitude_support(:flying, flight.merge(speed_p50: 80))).to eq(0)
    expect(TransportationModes::Emissions.altitude_support(:flying, flight.merge(altitude_p50: nil))).to eq(0)
    expect(TransportationModes::Emissions.altitude_support(:driving, flight)).to eq(0)
  end
  it 'ignores single altitude spikes and sparse altitude evidence' do
    expect(TransportationModes::Windower.altitude_median([{ altitude_m: 100 }, { altitude_m: 100 },
                                                          { altitude_m: 8000 }])).to eq(100)
    expect(TransportationModes::Windower.altitude_median([{ altitude_m: 8000 }, {}, {}])).to be_nil
  end
end
