# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::CacheCleaner do
  subject(:service) { described_class.new(user) }

  let(:user) { create(:user) }

  describe '#call' do
    context 'when cache supports delete_matched' do
      before do
        allow(Rails.cache).to receive(:respond_to?).and_return(true)
        allow(Rails.cache).to receive(:delete_matched)
      end

      it 'deletes photo cache entries for the user' do
        expect(Rails.cache).to receive(:delete_matched).with("photos_#{user.id}_*")
        service.call
      end

      it 'deletes thumbnail cache entries for the user' do
        expect(Rails.cache).to receive(:delete_matched).with("photo_thumbnail_#{user.id}_*")
        service.call
      end

      it 'calls both delete operations' do
        expect(Rails.cache).to receive(:delete_matched).twice
        service.call
      end
    end

    context 'when cache does not support delete_matched' do
      let(:cache_without_delete_matched) { double('Cache') }

      before do
        stub_const('Rails', double(cache: cache_without_delete_matched))
        allow(cache_without_delete_matched).to receive(:respond_to?).with(:delete_matched).and_return(false)
      end

      it 'does not attempt to delete cache entries' do
        expect(cache_without_delete_matched).not_to receive(:delete_matched)
        service.call
      end

      it 'does not raise an error' do
        expect { service.call }.not_to raise_error
      end
    end
  end

  describe '.call' do
    before do
      allow(Rails.cache).to receive(:respond_to?).and_return(true)
      allow(Rails.cache).to receive(:delete_matched)
    end

    it 'can be called as a class method' do
      expect(Rails.cache).to receive(:delete_matched).twice
      described_class.call(user)
    end

    it 'creates an instance and calls the instance method' do
      instance = instance_double(described_class)
      allow(described_class).to receive(:new).with(user).and_return(instance)
      expect(instance).to receive(:call)
      described_class.call(user)
    end
  end
end
