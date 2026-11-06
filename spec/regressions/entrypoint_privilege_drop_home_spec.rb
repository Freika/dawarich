# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# gosu sets HOME=/ for a PUID that has no /etc/passwd entry, and Bundler then
# warns that `/` is not writable on every start.
RSpec.describe 'Entrypoint writable HOME' do
  let(:guard_path) { File.expand_path('../../docker/entrypoint-env-guard.sh', __dir__) }

  def home_after_guard(home, app_path)
    script = 'set -e; . "$1"; ensure_writable_home; printf %s "$HOME"'
    Open3.capture2({ 'HOME' => home, 'APP_PATH' => app_path }, 'sh', '-c', script, 'sh', guard_path).first
  end

  # A missing directory is unwritable even for root, which a 0555 one is not.
  it 'moves HOME to the app tmp directory when HOME is not writable' do
    Dir.mktmpdir do |app_path|
      expect(home_after_guard(File.join(app_path, 'missing-home'), app_path)).to eq("#{app_path}/tmp")
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
