# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FeatureFlags do
  describe '.apply_defaults!' do
    it 'removes the retired poster ordering flag even when it was disabled' do
      Flipper.add(:poster_ordering)
      Flipper.disable(:poster_ordering)

      described_class.apply_defaults!

      expect(Flipper.exist?(:poster_ordering)).to be false
    end

    it 'removes the retired achievements flag' do
      Flipper.enable(:achievements)

      described_class.apply_defaults!

      expect(Flipper.exist?(:achievements)).to be false
    end

    it 'drops the instance settings flag now that the resolver always runs' do
      Flipper.add(:instance_settings_resolver)

      described_class.apply_defaults!

      expect(Flipper.exist?(:instance_settings_resolver)).to be false
    end

    it 'drops flags whose feature shipped unconditionally' do
      Flipper.add(:posters)

      described_class.apply_defaults!

      expect(Flipper.exist?(:posters)).to be false
    end
  end
end
