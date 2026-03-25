# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::ActivityTypeMapping do
  let(:test_class) { Class.new { include Imports::ActivityTypeMapping } }
  let(:instance) { test_class.new }

  describe '#map_activity_type' do
    # Google Semantic Segments types
    it { expect(instance.map_activity_type('IN_PASSENGER_VEHICLE')).to eq('driving') }
    it { expect(instance.map_activity_type('WALKING')).to eq('walking') }
    it { expect(instance.map_activity_type('CYCLING')).to eq('cycling') }
    it { expect(instance.map_activity_type('RUNNING')).to eq('running') }
    it { expect(instance.map_activity_type('FLYING')).to eq('flying') }
    it { expect(instance.map_activity_type('IN_BUS')).to eq('bus') }
    it { expect(instance.map_activity_type('IN_TRAIN')).to eq('train') }

    # TCX Sport types
    it { expect(instance.map_activity_type('Running')).to eq('running') }
    it { expect(instance.map_activity_type('Biking')).to eq('cycling') }

    # FIT sport types
    it { expect(instance.map_activity_type('trail_running')).to eq('running') }
    it { expect(instance.map_activity_type('mountain_biking')).to eq('cycling') }
    it { expect(instance.map_activity_type('hiking')).to eq('walking') }
    it { expect(instance.map_activity_type('walking')).to eq('walking') }
    it { expect(instance.map_activity_type('driving')).to eq('driving') }
    it { expect(instance.map_activity_type('flying')).to eq('flying') }

    # Unknown / nil
    it { expect(instance.map_activity_type('UNKNOWN')).to be_nil }
    it { expect(instance.map_activity_type(nil)).to be_nil }
    it { expect(instance.map_activity_type('Other')).to be_nil }
  end
end
