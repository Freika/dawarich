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
    # Both deployment topologies share the basic well-formedness checks
    # (scheme, host, blank-skip, DNS) and the always-blocked tier
    # (cloud metadata, multicast, reserved, link-local).
    shared_examples 'baseline checks' do
      it 'allows blank URLs' do
        expect { validator.validate_integration_url!('') }.not_to raise_error
      end

      it 'rejects non-http schemes' do
        expect { validator.validate_integration_url!('ftp://example.com') }
          .to raise_error(UrlValidatable::BlockedUrlError, /Invalid URL scheme/)
      end

      it 'rejects malformed URLs' do
        expect { validator.validate_integration_url!('not a url at all') }
          .to raise_error(UrlValidatable::BlockedUrlError, /Invalid URL/)
      end

      it 'rejects URLs that fail DNS resolution' do
        stub_unresolvable_host('nonexistent.local')

        expect { validator.validate_integration_url!('http://nonexistent.local') }
          .to raise_error(UrlValidatable::BlockedUrlError, /Could not resolve/)
      end

      describe 'always-blocked ranges (cloud metadata / multicast / reserved)' do
        {
          'all-zero 0.0.0.0/8'        => '0.0.0.0',
          'cloud metadata 169.254/16' => '169.254.169.254',
          'IPv4 multicast 224/4'      => '224.0.0.5',
          'IPv4 reserved 240/4'       => '240.0.0.5',
          'IPv6 link-local fe80::/10' => 'fe80::1',
          'IPv6 multicast ff00::/8'   => 'ff02::1'
        }.each do |label, ip|
          it "rejects #{label} (#{ip})" do
            stub_host_addresses('host.example', ip)
            expect { validator.validate_integration_url!('http://host.example/path') }
              .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
          end
        end
      end
    end

    context 'self-hosted (homelab) deployment' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      include_examples 'baseline checks'

      describe 'allows typical homelab targets' do
        {
          'IPv4 loopback 127.0.0.1' => '127.0.0.1',
          'RFC1918 10.x'            => '10.0.0.5',
          'RFC1918 172.16.x'        => '172.20.0.5',
          'RFC1918 192.168.x'       => '192.168.1.5',
          'CGNAT 100.64.x'          => '100.64.0.5',
          'IPv6 loopback ::1'       => '::1',
          'IPv6 ULA fc00::/7'       => 'fd00::1',
          'public IPv4'             => '93.184.216.34'
        }.each do |label, ip|
          it "permits #{label} (#{ip})" do
            stub_host_addresses('immich.lan', ip)
            expect { validator.validate_integration_url!('http://immich.lan:2283') }
              .not_to raise_error
          end
        end
      end

      it 'accepts a bracketed IPv6 literal host' do
        expect(validator.validate_integration_url!('http://[fd00::5]:2283')).to eq('fd00::5')
      end

      it 'rejects a LAN host that also resolves to the cloud metadata address' do
        stub_host_addresses('nas.lan', '192.168.1.5', '169.254.169.254')

        expect { validator.validate_integration_url!('http://nas.lan') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'permits Docker DNS hostnames resolving to bridge-network IPs' do
        stub_host_addresses('immich-server', '172.20.0.5')

        expect { validator.validate_integration_url!('http://immich-server:2283') }.not_to raise_error
      end

      it 'permits URLs with embedded credentials (Immich behind nginx basic-auth is a real homelab config)' do
        stub_host_addresses('immich.lan', '192.168.1.5')

        expect { validator.validate_integration_url!('http://user:pass@immich.lan/') }.not_to raise_error
      end
    end

    context 'cloud (dawarich.app) deployment' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      include_examples 'baseline checks'

      it 'allows valid public URLs' do
        stub_host_addresses('immich.example.com', '93.184.216.34')

        expect { validator.validate_integration_url!('https://immich.example.com') }.not_to raise_error
      end

      describe 'cloud-only blocked ranges (RFC1918 / CGNAT / loopback / ULA)' do
        {
          'IPv4 loopback 127.0.0.1' => '127.0.0.1',
          'localhost'               => '127.0.0.1',
          'RFC1918 10.x'            => '10.0.0.5',
          'RFC1918 172.16/12'       => '172.20.0.5',
          'RFC1918 192.168/16'      => '192.168.1.5',
          'CGNAT 100.64/10'         => '100.64.0.5',
          'IETF reserved 192.0.0/24' => '192.0.0.5',
          'benchmark 198.18/15'     => '198.19.0.5',
          'IPv6 loopback ::1'       => '::1',
          'IPv6 ULA fc00::/7'       => 'fd00::1'
        }.each do |label, ip|
          it "rejects #{label} (#{ip})" do
            stub_host_addresses('host.example', ip)
            expect { validator.validate_integration_url!('http://host.example/path') }
              .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
          end
        end
      end

      it 'rejects a host when any of its addresses is blocked' do
        stub_host_addresses('mixed.example.test', '93.184.216.34', '10.0.0.5')

        expect { validator.validate_integration_url!('http://mixed.example.test') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'rejects a host whose AAAA record maps to a private IPv4 address' do
        stub_host_addresses('mapped.example.test', '93.184.216.34', '::ffff:10.0.0.5')

        expect { validator.validate_integration_url!('http://mapped.example.test') }
          .to raise_error(UrlValidatable::BlockedUrlError, /blocked address/)
      end

      it 'returns the address the system resolver prefers' do
        stub_host_addresses('dual.example.test', '2606:2800:220:1::1', '93.184.216.34')

        expect(validator.validate_integration_url!('https://dual.example.test')).to eq('2606:2800:220:1::1')
      end

      it 'rejects a host that resolves to no addresses' do
        stub_host_addresses('empty.example.test')

        expect { validator.validate_integration_url!('http://empty.example.test') }
          .to raise_error(UrlValidatable::BlockedUrlError, /Could not resolve/)
      end

      it 'rejects URLs with userinfo' do
        expect { validator.validate_integration_url!('http://user:pass@example.com/') }
          .to raise_error(UrlValidatable::BlockedUrlError, /credentials/)
      end
    end
  end
end
