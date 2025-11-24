# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'devise/shared/_links.html.erb', type: :view do
  let(:resource_name) { :user }
  let(:devise_mapping) { Devise.mappings[:user] }

  before do
    def view.resource_name
      :user
    end

    def view.devise_mapping
      Devise.mappings[:user]
    end

    def view.resource_class
      User
    end

    def view.signed_in?
      false
    end
  end

  context 'with OIDC provider' do
    before do
      stub_const('OMNIAUTH_PROVIDERS', [:openid_connect])
      allow(User).to receive(:omniauth_providers).and_return([:openid_connect])
    end

    it 'displays custom OIDC provider name' do
      stub_const('OIDC_PROVIDER_NAME', 'Authentik')

      render

      expect(rendered).to have_button('Sign in with Authentik')
    end

    it 'displays default name when OIDC_PROVIDER_NAME is not set' do
      stub_const('OIDC_PROVIDER_NAME', 'Openid Connect')

      render

      expect(rendered).to have_button('Sign in with Openid Connect')
    end
  end

end
