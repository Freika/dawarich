# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::FixRouteOpacityJob, type: :job do
  describe '#perform' do
    it 'converts route_opacity > 1 by dividing by 100' do
      user = create(:user, settings: { 'route_opacity' => 60.0 })

      described_class.perform_now

      user.reload
      expect(user.settings['route_opacity']).to be_within(0.001).of(0.6)
    end

    it 'does not change route_opacity that is already 0-1' do
      user = create(:user, settings: { 'route_opacity' => 0.8 })

      described_class.perform_now

      user.reload
      expect(user.settings['route_opacity']).to eq(0.8)
    end

    it 'handles users without route_opacity setting' do
      user = create(:user, settings: {})

      expect { described_class.perform_now }.not_to raise_error

      user.reload
      expect(user.settings['route_opacity']).to be_nil
    end
  end
end
