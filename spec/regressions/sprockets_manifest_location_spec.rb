# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sprockets asset manifest' do
  it 'is stored outside the public directory' do
    expect(Rails.application.assets_manifest.filename)
      .not_to start_with(Rails.public_path.to_s)
  end
end
