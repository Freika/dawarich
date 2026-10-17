# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix port: the public/ file answers pinned in the Phoenix fixture' do
  let(:fixture) { PhoenixPublicFilesFixture.read }

  it 'matches the live settings and MIME types Phoenix mirrors when it serves public/' do
    expect(PhoenixPublicFilesFixture.settings).to eq(fixture['rails_settings'])
    expect(PhoenixPublicFilesFixture.mime_types(fixture['rails_mime_types'].keys)).to eq(fixture['rails_mime_types'])
  end

  it 'answers every recorded request the way Puma answered it when the fixture was written' do
    Dir.mktmpdir do |dir|
      root = File.join(dir, 'public')
      PhoenixPublicFilesFixture.build_tree(root, fixture['tree'])
      stacks = PhoenixPublicFilesFixture.stacks(root, fixture['application_hosts'])
      answers = fixture['requests'].to_h do |request|
        [request['name'], PhoenixPublicFilesFixture.rack_answer(stacks.fetch(request['stack']), request)]
      end

      expect(answers).to eq(fixture['requests'].to_h { |request| [request['name'], request['response']] })
    end
  end
end
