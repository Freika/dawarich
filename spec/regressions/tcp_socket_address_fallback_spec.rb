# frozen_string_literal: true

require 'rails_helper'
require 'resolv'

RSpec.describe 'SMTP address fallback' do
  it 'uses native resolution when the Ruby resolver returns an unreachable address' do
    server = TCPServer.new('127.0.0.1', 0)
    allow(Resolv).to receive(:getaddress).with('localhost').and_return('::1')

    socket = Net::SMTP.new('localhost').send(:tcp_socket, 'localhost', server.local_address.ip_port)

    expect(socket.remote_address).to be_ipv4
  ensure
    socket&.close
    server&.close
  end
end
