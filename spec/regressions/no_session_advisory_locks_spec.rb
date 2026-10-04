# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Session-level advisory locks behind PgBouncer transaction pooling' do
  let(:sources) { Dir[Rails.root.join('{app,lib,app-phoenix/lib}/**/*.{rb,rake,ex}')].sort }
  let(:allowed_session_gem_locks) { %w[app/services/phoenix_lease.rb] }

  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  it 'leaves no session advisory lock function call in Rails or Phoenix code' do
    offenders = sources.select { |path| File.read(path).match?(/pg_(try_)?advisory_(lock|unlock)(_shared|_all)?\(/i) }
    expect(offenders.map { relative(_1) }).to be_empty
  end

  it 'takes gem or Rails advisory locks only transaction-scoped, outside the listed files' do
    call = /\b(?:with_advisory_lock(?:_result)?!?|get_advisory_lock)(?=[\s(])/
    offenders = sources.select do |path|
      File.readlines(path).any? { |line| line.match?(call) && !line.include?('transaction: true') }
    end
    expect(offenders.map { relative(_1) }).to eq(allowed_session_gem_locks)
  end
end
