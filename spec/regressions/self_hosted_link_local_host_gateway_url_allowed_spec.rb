# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UrlValidatable do
  let(:test_class) do
    Class.new do
      include UrlValidatable
      public :validate_integration_url!
    end
  end

  subject(:validator) { test_class.new }

  describe '#validate_integration_url!' do
    context 'self-hosted (homelab) deployment' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'permits a container host-gateway hostname resolving to a link-local address' do
        stub_host_addresses('immich.mydomain', '169.254.1.2')

        expect { validator.validate_integration_url!('http://immich.mydomain') }.not_to raise_error
      end

      it 'still blocks the cloud metadata endpoint' do
        stub_host_addresses('metadata.host', '169.254.169.254')

        expect { validator.validate_integration_url!('http://metadata.host') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end
    end

    context 'cloud (dawarich.app) deployment' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'still blocks the cloud metadata endpoint' do
        stub_host_addresses('metadata.host', '169.254.169.254')

        expect { validator.validate_integration_url!('http://metadata.host') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'still blocks the wider link-local range' do
        stub_host_addresses('linklocal.host', '169.254.1.2')

        expect { validator.validate_integration_url!('http://linklocal.host') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end
    end
  end
end
