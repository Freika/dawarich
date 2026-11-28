# frozen_string_literal: true

require 'rails_helper'

# Every install, production included, starts with the documented demo admin.
RSpec.describe 'db/seeds.rb first user' do
  before do
    create(:country)
    create(:region)
    create(:disputed_area)
    Timezone.create!(tzid: 'Etc/UTC', geom: 'SRID=4326;POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))')
    allow(Rails.env).to receive(:production?).and_return(true)
    stub_const('ENV', ENV.to_h.merge('INITIAL_ADMIN_EMAIL' => 'admin@example.com',
                                     'INITIAL_ADMIN_PASSWORD' => 'another-password'))
  end

  it 'creates demo@dawarich.app with the documented password in production' do
    load Rails.root.join('db/seeds.rb')

    user = User.sole
    expect(user).to have_attributes(email: 'demo@dawarich.app', admin: true)
    expect(user.valid_password?('safepassword')).to be(true)
  end
end
