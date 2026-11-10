# frozen_string_literal: true

require 'rails_helper'
require 'zip'

# Regression: a cross-site GET must not claim an attacker-uploaded pending import
# into a signed-in victim's account.
RSpec.describe 'Pending import is not claimed by a cross-site GET', type: :request do
  let(:victim) { create(:user, status: :active, active_until: 1.year.from_now) }

  let(:pending) do
    path = Rails.root.join('tmp', "pend_#{SecureRandom.hex(4)}.zip").to_s
    ::Zip::File.open(path, create: true) do |z|
      z.get_output_stream('manifest.json') { |o| o.write('{"format_version":2,"counts":{},"files":{}}') }
    end
    pi = build(:pending_import, original_filename: 'attacker.zip')
    pi.file.attach(io: File.open(path), filename: 'attacker.zip', content_type: 'application/zip')
    pi.claim_ticket ||= SecureRandom.urlsafe_base64(24)
    pi.save!
    File.delete(path)
    pi
  end

  it 'does not claim on GET /users/sign_up?import_ticket while logged in' do
    sign_in victim

    expect do
      get '/users/sign_up', params: { import_ticket: pending.claim_ticket }
    end.not_to(change { victim.imports.count })

    expect(pending.reload.claimed_by_user_id).to be_nil
  end
end
