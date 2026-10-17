# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportCommands do
  fixture = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/wave4/commands.json').read)

  fixture.each do |type, spec|
    it "#{type} is version #{spec['version']} and produces exactly the fixture payload" do
      job_owner!("command:#{type}", :oban)

      described_class.public_send(type.delete_prefix('imports.'), spec['payload'].values.first, producer: 'spec')

      expect(JobCommands::COMMANDS.fetch(type)[:version]).to eq(spec['version'])
      expect(JobOutbox.pending.sole.payload).to eq(spec['payload'])
    end
  end
end
