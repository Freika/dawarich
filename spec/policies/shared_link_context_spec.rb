# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinkContext do
  def ctx(settings)
    described_class.new(SharedLink.new(settings: settings))
  end

  describe 'explicit opt-in sections (default OFF when absent)' do
    it 'show_photos? / show_stats? are true only when set to true' do
      expect(ctx({}).show_photos?).to be false
      expect(ctx({}).show_stats?).to be false
      expect(ctx('show_photos' => true).show_photos?).to be true
      expect(ctx('show_stats' => true).show_stats?).to be true
    end

    it 'show_day_notes? is true only when set to true' do
      expect(ctx({}).show_day_notes?).to be false
      expect(ctx('show_day_notes' => false).show_day_notes?).to be false
      expect(ctx('show_day_notes' => true).show_day_notes?).to be true
    end
  end

  describe 'core sections (default ON unless explicitly disabled)' do
    %w[show_route show_countries show_description show_days].each do |key|
      predicate = "#{key}?"

      it "#{predicate} defaults to true when the key is absent (backward compatible)" do
        expect(ctx({}).public_send(predicate)).to be true
      end

      it "#{predicate} is false only when explicitly set to false" do
        expect(ctx(key => false).public_send(predicate)).to be false
        expect(ctx(key => true).public_send(predicate)).to be true
      end
    end
  end
end
