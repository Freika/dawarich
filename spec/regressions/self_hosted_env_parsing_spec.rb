# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SELF_HOSTED environment parsing' do
  around do |example|
    example.run
  ensure
    load Rails.root.join('config/initializers/01_constants.rb')
  end

  def reload_constants_with_self_hosted(value)
    env = value.nil? ? ENV.to_hash.except('SELF_HOSTED') : ENV.to_hash.merge('SELF_HOSTED' => value)
    stub_const('ENV', env)
    load Rails.root.join('config/initializers/01_constants.rb')
  end

  context 'with values that mean self-hosted' do
    it 'treats a bare true as self-hosted' do
      reload_constants_with_self_hosted('true')
      expect(SELF_HOSTED).to be true
    end

    it 'treats a docker-compose quoted true as self-hosted' do
      reload_constants_with_self_hosted('"true"')
      expect(SELF_HOSTED).to be true
    end

    it 'treats an uppercase TRUE as self-hosted' do
      reload_constants_with_self_hosted('TRUE')
      expect(SELF_HOSTED).to be true
    end

    it 'treats a whitespace-padded true as self-hosted' do
      reload_constants_with_self_hosted(' true ')
      expect(SELF_HOSTED).to be true
    end

    it 'treats 1 as self-hosted' do
      reload_constants_with_self_hosted('1')
      expect(SELF_HOSTED).to be true
    end

    it 'defaults to self-hosted when unset' do
      reload_constants_with_self_hosted(nil)
      expect(SELF_HOSTED).to be true
    end
  end

  context 'with values that mean cloud' do
    it 'treats false as cloud' do
      reload_constants_with_self_hosted('false')
      expect(SELF_HOSTED).to be false
    end

    it 'treats an empty string as cloud' do
      reload_constants_with_self_hosted('')
      expect(SELF_HOSTED).to be false
    end
  end
end
