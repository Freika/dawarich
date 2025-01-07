# frozen_string_literal: true

return if User.any?

puts 'Creating user...'

User.create!(
  email: 'demo@dawarich.app',
  password: 'password',
  password_confirmation: 'password',
  admin: true
)

puts "User created: #{User.first.email} / password: 'password'"
