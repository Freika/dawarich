# frozen_string_literal: true

return if User.any?

User.create!(
  email: 'user@domain.com',
  password: 'password',
  password_confirmation: 'password',
  admin: true
)

puts "User created: #{User.first.email} / password: 'password'"
