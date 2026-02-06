# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::DeduplicationJob do
  describe 'queue configuration' do
    it 'uses the tracks queue' do
      expect(described_class.queue_name).to eq('tracks')
    end
  end

  describe '#perform' do
    context 'when user exists' do
      let(:user) { create(:user) }

      it 'calls Tracks::Deduplicator' do
        deduplicator = instance_double(Tracks::Deduplicator, call: 0)
        allow(Tracks::Deduplicator).to receive(:new).with(user).and_return(deduplicator)

        described_class.new.perform(user.id)

        expect(deduplicator).to have_received(:call)
      end
    end

    context 'when user does not exist' do
      it 'returns early without error' do
        expect(Tracks::Deduplicator).not_to receive(:new)

        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end
  end
end
