# frozen_string_literal: true

# https://makandracards.com/makandra/37161-rspec-devise-how-to-sign-in-users-in-request-specs

module DeviseRequestSpecHelpers
  include Warden::Test::Helpers

  def sign_in(resource_or_scope, resource = nil)
    resource ||= resource_or_scope
    scope = Devise::Mapping.find_scope!(resource_or_scope)
    login_as(resource, scope: scope)
  end

  def sign_out(resource_or_scope)
    scope = Devise::Mapping.find_scope!(resource_or_scope)
    logout(scope)
  end

end

RSpec.configure do |config|
  config.include DeviseRequestSpecHelpers, type: :request
end
