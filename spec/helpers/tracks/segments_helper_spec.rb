# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::SegmentsHelper, type: :helper do
  describe '#modes_for_mode' do
    let(:user) { create(:user, settings: { 'enabled_transportation_modes' => %w[walking driving] }) }

    before do
      # No signed-in helper user, so the method reads the passed user's own
      # settings — the branch that matters here is how options get built.
      allow(helper).to receive(:current_user).and_return(nil)
    end

    it 'offers every mode the user has enabled' do
      expect(helper.modes_for_mode('walking', user).map(&:last)).to eq(%w[walking driving])
    end

    it 'keeps a disabled current mode selectable so an override is never silently lost' do
      options = helper.modes_for_mode('cycling', user)

      expect(options.map(&:last)).to eq(%w[cycling walking driving])
      expect(options.first.first).to include(I18n.t('transportation_modes.cycling'))
    end

    it 'agrees with the segment-based helper it backs' do
      segment = build_stubbed(:track_segment, transportation_mode: 'cycling')

      expect(helper.modes_for_segment(segment, user)).to eq(helper.modes_for_mode('cycling', user))
    end
  end

  describe '#mode_icon_name' do
    it 'maps known modes to lucide icons that exist in the vendored set' do
      %w[walking running cycling driving bus train flying boat motorcycle stationary unknown].each do |mode|
        name = helper.mode_icon_name(mode)
        path = Rails.root.join("app/assets/svg/icons/lucide/outline/#{name}.svg")

        expect(path).to exist, "#{mode} -> #{name}.svg is not vendored"
      end
    end

    it 'falls back to a generic marker for an unrecognised mode' do
      expect(helper.mode_icon_name('teleporting')).to eq('route')
    end
  end
end
