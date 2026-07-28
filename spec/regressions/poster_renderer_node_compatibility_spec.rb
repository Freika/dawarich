# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Poster renderer Node compatibility' do
  let(:launcher) { Rails.root.join('vendor/poster_renderer/render.sh') }

  def run_launcher(register_supported:)
    Dir.mktmpdir('poster-renderer-node') do |dir|
      args_path = File.join(dir, 'args')
      node_path = File.join(dir, 'node')
      File.write(node_path, <<~SH)
        #!/bin/sh
        if [ "$1" = "-e" ]; then
          exit #{register_supported ? 0 : 1}
        fi
        printf '%s\\n' "$@" > #{Shellwords.escape(args_path)}
      SH
      FileUtils.chmod(0o755, node_path)

      success = system({ 'PATH' => "#{dir}:#{ENV.fetch('PATH')}" }, launcher.to_s, 'job.json')
      [success, File.readlines(args_path, chomp: true)]
    end
  end

  it 'uses the loader flag supported by older Node releases' do
    success, args = run_launcher(register_supported: false)

    expected_prefix = [
      '--experimental-loader',
      Rails.root.join('vendor/poster_renderer/loader.mjs').to_s
    ]
    expected_suffix = [Rails.root.join('vendor/poster_renderer/render.mjs').to_s, 'job.json']

    expect(success).to be(true)
    expect(args.first(2)).to eq(expected_prefix)
    expect(args.last(2)).to eq(expected_suffix)
  end

  it 'uses the import registration path when Node supports it' do
    success, args = run_launcher(register_supported: true)

    expected_prefix = [
      '--import',
      Rails.root.join('vendor/poster_renderer/register.mjs').to_s
    ]

    expect(success).to be(true)
    expect(args.first(2)).to eq(expected_prefix)
  end
end
