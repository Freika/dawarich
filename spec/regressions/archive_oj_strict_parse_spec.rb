# frozen_string_literal: true

require 'rails_helper'

# Regression: user-data archive JSONL must be parsed as plain data (Oj :strict),
# so an object directive like ^o cannot instantiate arbitrary Ruby classes.
RSpec.describe 'Archive import parses JSONL as data, not Oj object mode' do
  let(:user) { create(:user, settings: {}) }
  let(:dir) { Rails.root.join('tmp', "oj_#{SecureRandom.hex(4)}") }

  around do |example|
    FileUtils.mkdir_p(dir)
    example.run
    FileUtils.rm_rf(dir)
  end

  it 'stores an ^o payload as an inert Hash, not an instantiated Object' do
    File.write(dir.join('settings.jsonl'), %({"probe":{"^o":"Object","x":1}}\n))
    handler = Users::ImportData::V2Handler.new(user, dir, { settings_updated: false })

    handler.send(:import_settings)

    probe = user.reload.settings['probe']
    expect(probe).to be_a(Hash)
    expect(probe).to eq('^o' => 'Object', 'x' => 1)
  end
end
