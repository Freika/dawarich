# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reading instance settings before their table exists' do
  before do
    ActiveRecord::Base.connection.execute('ALTER TABLE instance_settings RENAME TO instance_settings_hidden')
    InstanceSettings::Resolver.reset!
  end

  it 'leaves the surrounding transaction usable' do
    ActiveRecord::Base.transaction do
      expect(DawarichSettings.reverse_geocoding_enabled?).to be(false)
      expect(ActiveRecord::Base.connection.select_value('SELECT 1')).to eq(1)
    end
  end
end
