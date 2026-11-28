# frozen_string_literal: true

{
  pl: {
    i18n: {
      plural: {
        rule: lambda do |count|
          next :other unless count.is_a?(Integer)

          n = count.abs
          if n == 1
            :one
          elsif (2..4).cover?(n % 10) && !(12..14).cover?(n % 100)
            :few
          else
            :many
          end
        end
      }
    }
  }
}
