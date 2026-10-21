# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_b10_admin' do
  around do |example|
    original = ENV['E2E_B9_B11_FIXTURES']
    ENV['E2E_B9_B11_FIXTURES'] = '1'
    example.run
  ensure
    ENV['E2E_B9_B11_FIXTURES'] = original
  end

  it 'creates an administrator without changing the shared demo user' do
    demo = User.find_by(email: 'demo@dawarich.app') || create(:user, email: 'demo@dawarich.app')
    original_admin = demo.admin?

    Rake::Task['e2e:seed_b10_admin'].execute

    admin = User.find_by!(email: 'b10-admin@dawarich.test')
    expect(admin.admin?).to be(true)
    expect(admin.valid_password?('safepassword12')).to be(true)
    expect(demo.reload.admin?).to eq(original_admin)
  end

  it 'is idempotent' do
    2.times { Rake::Task['e2e:seed_b10_admin'].execute }

    expect(User.where(email: 'b10-admin@dawarich.test').count).to eq(1)
  end
end
