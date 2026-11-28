# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SMTP host resolution' do
  let(:host) { 'smtp.dual-stack.invalid' }

  before { Rails.cache.delete("dawarich/dns:#{host}") }

  it 'connects over IPv4 when the host lists an unreachable IPv6 address first' do
    server = TCPServer.new('127.0.0.1', 0)
    allow(Resolv::DefaultResolver).to receive(:each_address).with(host).and_yield('::1').and_yield('127.0.0.1')

    socket = Net::SMTP.new(host).send(:tcp_socket, host, server.local_address.ip_port)

    expect(socket.remote_address).to be_ipv4
  ensure
    socket&.close
    server&.close
  end
end
