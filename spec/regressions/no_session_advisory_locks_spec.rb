# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Session-level advisory locks behind PgBouncer transaction pooling' do
  let(:pre_existing) { %w[app/services/stats/toponyms_refresh.rb] }

  it 'leaves no session advisory lock call in Rails or Phoenix code' do
    offenders = Dir[Rails.root.join('{app,app-phoenix/lib}/**/*.{rb,ex}')].filter_map do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      relative if File.read(path).match?(/pg_(try_)?advisory_(lock|unlock)(_shared|_all)?\(/i)
    end
    expect(offenders - pre_existing).to be_empty
  end
end
