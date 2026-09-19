# frozen_string_literal: true

# resolv-replace makes TCPSocket resolve a host to one address before connecting.
# That removes Ruby's native address fallback (for example, unreachable IPv6 to
# reachable IPv4). Keep resolv-replace and Dawarich's DNS cache for all ordinary
# socket users, but let SMTP use the original TCPSocket initializer instead.
Rails.application.config.after_initialize do
  next unless TCPSocket.private_instance_methods.include?(:original_resolv_initialize)

  Net::SMTP.prepend(Module.new do
    private

    def tcp_socket(address, port)
      socket = TCPSocket.allocate
      socket.__send__(:original_resolv_initialize, address, port)
      socket
    end
  end)
end
