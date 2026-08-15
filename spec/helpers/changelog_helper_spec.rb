# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangelogHelper, type: :helper do
  describe '#chibichange_widget_src' do
    it 'builds the widget loader src from the configured host' do
      stub_const('CHIBICHANGE_WIDGET_HOST', 'https://my.chibichange.com')
      expect(helper.chibichange_widget_src).to eq('https://my.chibichange.com/w/v1/loader.js')
    end
  end

  describe '#chibichange_slug' do
    context 'on cloud (not self-hosted)' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'returns the cloud slug' do
        stub_const('CHIBICHANGE_CLOUD_SLUG', 'dawarich-cloud')
        expect(helper.chibichange_slug).to eq('dawarich-cloud')
      end
    end

    context 'on self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'returns the self-hosted slug' do
        stub_const('CHIBICHANGE_SLUG', 'dawarich')
        expect(helper.chibichange_slug).to eq('dawarich')
      end
    end
  end

  describe '#changelog_indicator_state' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted) }

    context 'when the user is signed out (nil)' do
      let(:self_hosted) { false }

      it { expect(helper.changelog_indicator_state(nil)).to eq(:badge) }
    end

    context 'on cloud (not self-hosted), signed in' do
      let(:self_hosted) { false }

      it 'shows the widget without prompting, even when consent is nil' do
        user = build(:user, changelog_consent: nil)
        expect(helper.changelog_indicator_state(user)).to eq(:widget)
      end

      it 'shows the widget when consent granted' do
        user = build(:user, changelog_consent: :granted)
        expect(helper.changelog_indicator_state(user)).to eq(:widget)
      end

      it 'respects an explicit opt-out by showing the plain badge' do
        user = build(:user, changelog_consent: :declined)
        expect(helper.changelog_indicator_state(user)).to eq(:badge)
      end
    end

    context 'on self-hosted, signed in' do
      let(:self_hosted) { true }

      it 'shows the widget when consent granted' do
        user = build(:user, changelog_consent: :granted)
        expect(helper.changelog_indicator_state(user)).to eq(:widget)
      end

      it 'prompts when consent is pending (nil)' do
        user = build(:user, changelog_consent: nil)
        expect(helper.changelog_indicator_state(user)).to eq(:prompt)
      end

      it 'shows the plain badge when consent declined' do
        user = build(:user, changelog_consent: :declined)
        expect(helper.changelog_indicator_state(user)).to eq(:badge)
      end
    end
  end
end
