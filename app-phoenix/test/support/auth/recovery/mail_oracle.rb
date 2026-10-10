# frozen_string_literal: true

require 'digest'
require_relative 'oracle_support'

RAW = 'safe-synthetic-raw'
rows = %w[en de fr es pl ca zh].flat_map do |locale|
  user = User.new(email: 'recovery&safe@dawarich.test', settings: { 'locale' => locale })
  %i[reset_password_instructions unlock_instructions].map do |kind|
    mail = DeviseMailer.public_send(kind, user, RAW)
    mail.date = RecoveryOracle::NOW
    mail.message_id = '<a11-recovery-oracle@dawarich.test>'
    html = mail.body.decoded
    wire = mail.encoded
    parsed = Mail.read_from_string(wire)
    {
      kind:, locale:, email: user.email, raw: RAW, subject: mail.subject, from: mail.from, to: mail.to,
      content_type: mail.mime_type, html:, wire_html: parsed.body.decoded,
      wire_transfer_encoding: parsed.content_transfer_encoding, wire_charset: parsed.charset,
      wire_reply_to: parsed.reply_to, wire_sender: parsed.sender, wire_sha256: Digest::SHA256.hexdigest(wire),
      mail_version: Gem.loaded_specs.fetch('mail').version.to_s
    }
  end
end

RecoveryOracle.write(ARGV.fetch(0), rows)
puts "Captured #{rows.size} recovery mail renderings without delivery"
