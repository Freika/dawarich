# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Export, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(created: 0, processing: 1, completed: 2, failed: 3) }
    it { is_expected.to define_enum_for(:file_format).with_values(json: 0, gpx: 1) }
  end
end
