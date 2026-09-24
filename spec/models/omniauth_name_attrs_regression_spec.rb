# frozen_string_literal: true

require 'rails_helper'

# Regression guard for `Omniauthable#omniauth_name_attrs`: it must read the raw
# `info[:name]` claim, not `OmniAuth::AuthHash::InfoHash#name`, whose fallback
# chain returns `nickname` (a GitHub login) or `email` when `:name` is absent.
RSpec.describe 'omniauth_name_attrs regression', type: :model do
  let(:suffix) { "#{Time.now.to_i}-#{SecureRandom.hex(4)}" }

  describe 'Omniauthable#omniauth_name_attrs (private)' do
    def call_omniauth_name_attrs(info)
      auth = OmniAuth::AuthHash.new(provider: 'github', uid: "uid-#{suffix}", info: info)
      User.send(:omniauth_name_attrs, auth)
    end

    it 'returns no first_name when the provider omits :name and only nickname is set' do
      result = call_omniauth_name_attrs(nickname: 'alice_login', email: "alice-#{suffix}@example.com", name: nil)

      expect(result).to eq({})
    end

    it 'returns no first_name when only email is present (:name absent entirely)' do
      result = call_omniauth_name_attrs(email: "min-#{suffix}@example.com")

      expect(result).to eq({})
    end

    it 'does not consult the synthesized InfoHash#name (which would fall back to nickname)' do
      info = OmniAuth::AuthHash::InfoHash.new(nickname: 'alice_login', email: "alice-#{suffix}@example.com", name: nil)

      expect(info.name).to eq('alice_login')
      expect(call_omniauth_name_attrs(info)).to eq({})
    end

    it 'splits a real :name claim into first/last name' do
      expect(call_omniauth_name_attrs(name: 'Ada Lovelace')).to eq(first_name: 'Ada', last_name: 'Lovelace')
    end
  end

  describe 'User.from_omniauth persistence (GitHub no-name reachable case)' do
    let(:no_name_auth) do
      OmniAuth::AuthHash.new(
        provider: 'github',
        uid: "reg-#{suffix}",
        info: { nickname: 'alice_login', email: "alice-#{suffix}@example.com", name: nil },
        extra: { raw_info: { login: 'alice_login', name: nil } }
      )
    end

    it 'does not synthesize a first_name from the GitHub login when name is null' do
      user = User.from_omniauth(no_name_auth)
      reloaded = User.find(user.id)

      expect(user.first_name).to be_nil
      expect(user.last_name).to be_nil
      expect(reloaded.first_name).to be_nil
      expect(reloaded.last_name).to be_nil
    end
  end
end
