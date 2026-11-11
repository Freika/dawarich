# frozen_string_literal: true

require 'rails_helper'

# Regression: the IPv6 unspecified address '::' routes to the local host on
# connect, so it must be rejected on every topology like ::1 and fc00::/7.
RSpec.describe 'Integration URLs targeting the IPv6 unspecified address ::' do
  let(:test_class) do
    Class.new do
      include UrlValidatable
      public :validate_integration_url!
    end
  end

  subject(:validator) { test_class.new }

  it 'rejects http://[::]:3000/ on cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { validator.validate_integration_url!('http://[::]:3000/') }
      .to raise_error(UrlValidatable::BlockedUrlError, /blocked/i)
  end

  it 'rejects http://[::]:3000/ on self-hosted too (always-blocked tier)' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    expect { validator.validate_integration_url!('http://[::]:3000/') }
      .to raise_error(UrlValidatable::BlockedUrlError, /blocked/i)
  end

  it 'still allows a routable IPv6 address' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_host_addresses('immich.example.test', '2606:2800:220:1::1')

    expect { validator.validate_integration_url!('http://immich.example.test') }.not_to raise_error
  end
end
