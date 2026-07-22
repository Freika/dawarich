# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'DNS cache initializer' do
  it 'lets the original resolver raise for nil names' do
    expect { Resolv.getaddress(nil) }.to raise_error(ArgumentError, /cannot interpret as DNS name/)
  end

  it 'still short-circuits IP address literals' do
    expect(Resolv.getaddress('127.0.0.1')).to eq('127.0.0.1')
  end
end
