# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# gosu sets HOME=/ for a PUID that has no /etc/passwd entry, and Bundler then
# warns that `/` is not writable on every start (#3917).
RSpec.describe 'Entrypoint writable HOME' do
  let(:guard_path) { File.expand_path('../../docker/entrypoint-env-guard.sh', __dir__) }

  def home_after_guard(home, app_path)
    script = "set -e; . #{guard_path}; ensure_writable_home; printf %s \"$HOME\""
    Open3.capture2({ 'HOME' => home, 'APP_PATH' => app_path }, 'sh', '-c', script).first
  end

  it 'moves HOME to the app tmp directory when HOME is not writable' do
    Dir.mktmpdir do |app_path|
      read_only_home = File.join(app_path, 'home')
      Dir.mkdir(read_only_home, 0o555)

      expect(home_after_guard(read_only_home, app_path)).to eq("#{app_path}/tmp")
    end
  end

  it 'keeps a writable HOME' do
    Dir.mktmpdir do |home|
      expect(home_after_guard(home, '/var/app')).to eq(home)
    end
  end

  %w[web-entrypoint.sh sidekiq-entrypoint.sh].each do |name|
    it "#{name} applies the guard after dropping privileges" do
      script = File.read(File.expand_path("../../docker/#{name}", __dir__))

      expect(script.index('ensure_writable_home')).to be > script.index('exec gosu')
    end
  end
end
