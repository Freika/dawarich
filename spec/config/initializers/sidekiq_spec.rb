# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sidekiq initializer' do
  describe 'yabeda-sidekiq integration' do
    it 'registers the sidekiq metric group when the gem is required' do
      require 'yabeda/sidekiq'
      expect(Yabeda.groups.key?(:sidekiq)).to be true
    end
  end
end
