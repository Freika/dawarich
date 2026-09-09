# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FeatureFlags do
  describe '.apply_defaults!' do
    it 'ships poster ordering enabled on an install that has never seen the flag' do
      Flipper.remove(:poster_ordering)

      described_class.apply_defaults!

      expect(Flipper.enabled?(:poster_ordering)).to be true
    end

    it 'leaves an instance that turned poster ordering off alone' do
      Flipper.add(:poster_ordering)
      Flipper.disable(:poster_ordering)

      described_class.apply_defaults!

      expect(Flipper.enabled?(:poster_ordering)).to be false
    end

    it 'drops flags whose feature shipped unconditionally' do
      Flipper.add(:posters)

      described_class.apply_defaults!

      expect(Flipper.exist?(:posters)).to be false
    end
  end
end
