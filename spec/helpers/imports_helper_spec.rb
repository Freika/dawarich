# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportsHelper do
  describe '#extraction_status_badge' do
    subject(:badge) { helper.extraction_status_badge(import) }

    let(:import) { build(:import, additional_data_extraction_status: status) }

    context 'when not attempted' do
      let(:status) { :not_attempted }

      it 'renders a neutral badge' do
        expect(badge).to have_css('span.badge.badge-ghost', text: 'Not extracted')
      end
    end

    context 'when pending' do
      let(:status) { :pending }

      it 'renders a queued badge' do
        expect(badge).to have_css('span.badge.badge-info', text: 'Queued')
      end
    end

    context 'when running' do
      let(:status) { :running }

      it 'renders a spinner alongside the label' do
        expect(badge).to have_css('span.badge.badge-info span.loading.loading-dots')
        expect(badge).to have_css('span.badge', text: 'Extracting')
      end
    end

    context 'when completed' do
      let(:status) { :completed }

      it 'renders a success badge' do
        expect(badge).to have_css('span.badge.badge-success', text: 'Extracted')
      end
    end

    context 'when failed' do
      let(:status) { :failed }

      it 'renders an error badge' do
        expect(badge).to have_css('span.badge.badge-error', text: 'Failed')
      end
    end

    context 'when unsupported' do
      let(:status) { :unsupported }

      it 'renders an unavailable badge' do
        expect(badge).to have_css('span.badge.badge-ghost', text: 'Not available')
      end
    end

    context 'when the status is unrecognised' do
      let(:status) { :not_attempted }

      it 'renders nothing' do
        allow(import).to receive(:additional_data_extraction_status).and_return('bogus')

        expect(helper.extraction_status_badge(import)).to be_nil
      end
    end
  end
end
