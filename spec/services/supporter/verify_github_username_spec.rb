# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Supporter::VerifyGithubUsername do
  let(:verify_url) { 'https://verify.dawarich.app/api/v1/verify' }

  describe '#call' do
    it 'returns supporter: false for a blank username' do
      expect(described_class.new('').call).to eq({ supporter: false })
    end

    it 'queries the verification service by github_username and returns the result' do
      stub_request(:get, verify_url)
        .with(query: { github_username: 'octocat' })
        .to_return(status: 200, body: { supporter: true, platform: 'github' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(described_class.new('octocat').call).to eq({ supporter: true, platform: 'github' })
    end

    it 'normalizes the username to lowercase before querying' do
      stub = stub_request(:get, verify_url)
             .with(query: { github_username: 'octocat' })
             .to_return(status: 200, body: { supporter: true, platform: 'github' }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      described_class.new('OctoCat').call

      expect(stub).to have_been_requested
    end

    it 'returns supporter: false when the service responds with an error' do
      stub_request(:get, verify_url)
        .with(query: { github_username: 'octocat' })
        .to_return(status: 500)

      expect(described_class.new('octocat').call).to eq({ supporter: false })
    end

    it 'returns supporter: false when the request raises' do
      stub_request(:get, verify_url)
        .with(query: { github_username: 'octocat' })
        .to_raise(SocketError)

      expect(described_class.new('octocat').call).to eq({ supporter: false })
    end
  end
end
