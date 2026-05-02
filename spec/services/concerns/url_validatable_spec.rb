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

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  describe '#validate_integration_url!' do
    context 'when self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'skips validation entirely' do
        expect { validator.validate_integration_url!('http://127.0.0.1:2283') }.not_to raise_error
      end
    end

    context 'when not self-hosted' do
      it 'allows valid public URLs' do
        allow(Resolv).to receive(:getaddress).with('immich.example.com').and_return('93.184.216.34')

        expect { validator.validate_integration_url!('https://immich.example.com') }.not_to raise_error
      end

      it 'rejects blank URLs' do
        expect { validator.validate_integration_url!('') }.not_to raise_error
      end

      it 'rejects non-http schemes' do
        expect { validator.validate_integration_url!('ftp://example.com') }
          .to raise_error(UrlValidatable::BlockedUrlError, /Invalid URL scheme/)
      end

      it 'rejects localhost' do
        allow(Resolv).to receive(:getaddress).with('localhost').and_return('127.0.0.1')

        expect { validator.validate_integration_url!('http://localhost:2283') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'rejects 127.0.0.1' do
        allow(Resolv).to receive(:getaddress).with('127.0.0.1').and_return('127.0.0.1')

        expect { validator.validate_integration_url!('http://127.0.0.1:2283') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'rejects cloud metadata IP 169.254.169.254' do
        allow(Resolv).to receive(:getaddress).with('169.254.169.254').and_return('169.254.169.254')

        expect { validator.validate_integration_url!('http://169.254.169.254/latest/meta-data') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'rejects 0.0.0.0' do
        allow(Resolv).to receive(:getaddress).with('0.0.0.0').and_return('0.0.0.0')

        expect { validator.validate_integration_url!('http://0.0.0.0:2283') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'rejects URLs that fail DNS resolution' do
        allow(Resolv).to receive(:getaddress).with('nonexistent.local').and_raise(Resolv::ResolvError)

        expect { validator.validate_integration_url!('http://nonexistent.local') }
          .to raise_error(UrlValidatable::BlockedUrlError, /Could not resolve/)
      end

      it 'rejects malformed URLs' do
        expect { validator.validate_integration_url!('not a url at all') }
          .to raise_error(UrlValidatable::BlockedUrlError, /Invalid URL/)
      end

      describe 'expanded blocklist (audit C-3)' do
        {
          'RFC1918 10/8'           => '10.0.0.5',
          'RFC1918 172.16/12'      => '172.20.0.5',
          'RFC1918 192.168/16'     => '192.168.1.5',
          'CGNAT 100.64/10'        => '100.64.0.5',
          'IETF reserved 192.0.0/24' => '192.0.0.5',
          'benchmark 198.18/15'    => '198.19.0.5',
          'multicast 224/4'        => '224.0.0.5',
          'reserved 240/4'         => '240.0.0.5',
          'IPv6 ULA fc00::/7'      => 'fd00::1',
          'IPv6 multicast ff00::/8' => 'ff02::1'
        }.each do |label, ip|
          it "rejects #{label} (#{ip})" do
            allow(Resolv).to receive(:getaddress).with('host.example').and_return(ip)
            expect { validator.validate_integration_url!('http://host.example/path') }
              .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
          end
        end

        it 'rejects URLs with userinfo' do
          expect { validator.validate_integration_url!('http://user:pass@example.com/') }
            .to raise_error(UrlValidatable::BlockedUrlError, /credentials/)
        end
      end
    end
  end
end
