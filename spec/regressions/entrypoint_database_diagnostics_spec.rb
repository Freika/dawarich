# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe 'Web entrypoint database diagnostics' do
  let(:function) do
    File.read(File.expand_path('../../docker/web-entrypoint.sh', __dir__))
        .split('create_database() {', 2).last.split("\n# Step 1:", 2).first
        .prepend('create_database() {')
  end

  def run_database(check)
    stubs = <<~SH
      createdb() { echo 'database already exists' >&2; return 1; }
      psql() { #{check}; }
      sleep() { exit 42; }
    SH
    Open3.capture3('sh', '-c',
                   "set -e\n#{stubs}\n#{function}\ncreate_database dawarich_test_3105 secret localhost 5432 postgres")
  end

  it 'prints the connection error before retrying without exposing the password' do
    _, stderr, status = run_database("echo 'connection refused' >&2; return 1")
    expect(status.exitstatus).to eq(42)
    expect(stderr).to include('connection refused', 'unavailable - retrying')
    expect(stderr).not_to include('secret', 'database already exists')
  end

  it 'keeps stderr quiet when the database already exists and is reachable' do
    _, stderr, status = run_database('return 0')
    expect(status).to be_success
    expect(stderr).to be_empty
  end
end
