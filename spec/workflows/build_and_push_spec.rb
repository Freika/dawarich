# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tempfile'

RSpec.describe 'Docker image build tags' do
  let(:workflow) { YAML.load_file(File.expand_path('../../.github/workflows/build_and_push.yml', __dir__)) }
  let(:tag_script) do
    workflow.fetch('jobs').fetch('merge').fetch('steps').find { |step| step['id'] == 'docker_tags' }.fetch('run')
  end

  def tags_for(event:, prerelease:)
    substitutions = {
      '${{ secrets.DOCKERHUB_USERNAME }}' => 'test',
      '${{ needs.prepare.outputs.version }}' => 'test-version',
      '${{ needs.prepare.outputs.is_prerelease }}' => prerelease.to_s
    }
    script = tag_script.gsub(/\$\{\{[^}]+\}\}/) { |expression| substitutions.fetch(expression) }

    Tempfile.create('docker-tags') do |output|
      stdout, stderr, status = Open3.capture3({ 'GITHUB_EVENT_NAME' => event, 'GITHUB_OUTPUT' => output.path },
                                              'bash', '-e', '-c', script)
      expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
      File.read(output.path).lines.find { |line| line.start_with?('tags=') }.strip.delete_prefix('tags=').split(',')
    end
  end

  it 'never publishes latest from a manual dispatch' do
    expect(tags_for(event: 'workflow_dispatch', prerelease: false)).to eq(['test/dawarich:test-version'])
  end

  it 'publishes latest for a stable release' do
    expect(tags_for(event: 'release', prerelease: false)).to include('test/dawarich:latest')
  end

  it 'publishes rc without latest for a prerelease' do
    expect(tags_for(event: 'release', prerelease: true))
      .to contain_exactly('test/dawarich:test-version', 'test/dawarich:rc')
  end
end
