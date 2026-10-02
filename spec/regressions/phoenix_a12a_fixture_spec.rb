# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix port: the ActionCable facts A12a recorded, read with the live Rails settings' do
  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/a12a') }
  let(:cable) { JSON.parse(dir.join('cable.json').read) }
  let(:phoenix) { JSON.parse(dir.join('phoenix.json').read) }

  def untag(value)
    case value
    when Array then value.map { |inner| untag(inner) }
    when Hash
      return Float(value['float']) if value.key?('float')

      value['object'].to_h { |key, inner| [key, untag(inner)] }
    else value
    end
  end

  it 'keeps the protocol constants Phoenix reproduces' do
    expect(ActionCable::INTERNAL.as_json).to eq(cable['constants']['internal'])
    expect(ActionCable::Server::Connections::BEAT_INTERVAL).to eq(cable['constants']['beat_interval'])
  end

  it 'channel set unchanged' do
    Rails.application.eager_load!
    channels = ActionCable::Channel::Base.descendants.sort_by(&:name)
    expect(channels.map(&:name)).to eq(cable['constants']['descendants'])
    expect(channels.to_h { |c| [c.name, c.channel_name] }).to eq(cable['constants']['channel_names'])
  end

  it 'encodes every recorded producer input to the recorded payload' do
    cable['producers'].each do |producer|
      expect(ActiveSupport::JSON.encode(untag(producer['input']))).to eq(producer['payload'])
    end
  end

  it 'every phoenix.json payload equals the recorded Rails payload' do
    rails = cable['producers'].map { |p| p.slice('name', 'broadcasting', 'payload') }
    expect(phoenix['producers']).to eq(rails)
  end
end
