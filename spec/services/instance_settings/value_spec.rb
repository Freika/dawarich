# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSettings::Value do
  def build(source:, value: 'photon.example.com')
    described_class.new(key: :photon_api_host, value: value, source: source, env_var: 'PHOTON_API_HOST')
  end

  describe '#pinned?' do
    it 'is pinned only when the environment supplied the value' do
      expect(build(source: :env)).to be_pinned
      expect(build(source: :stored)).not_to be_pinned
      expect(build(source: :default)).not_to be_pinned
    end
  end

  it 'exposes the variable that pins it so the UI can name it' do
    expect(build(source: :env).env_var).to eq('PHOTON_API_HOST')
  end

  it 'rejects a source outside the three the resolver can report' do
    expect { build(source: :guesswork) }.to raise_error(ArgumentError, /source/)
  end

  it 'carries the resolved value' do
    expect(build(source: :stored, value: 'stored.example.com').value).to eq('stored.example.com')
  end
end
