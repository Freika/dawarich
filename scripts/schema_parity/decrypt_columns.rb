# frozen_string_literal: true

require 'base64'

side, list, out = ARGV
connection = ActiveRecord::Base.connection
unless connection.select_value('SHOW transaction_read_only') == 'on'
  abort "decrypt_columns.rb: the #{side} side's session is not read-only"
end

statements = File.readlines(list, chomp: true).flat_map do |line|
  table, column = line.split("\t")
  next [] unless connection.column_exists?(table, column)

  model = table.classify.constantize
  unless model.table_name == table && model.encrypted_attributes.include?(column.to_sym)
    abort "decrypt_columns.rb: #{table}.#{column} is not an attribute #{model} encrypts"
  end

  type = model.type_for_attribute(column)
  quoted_table = connection.quote_table_name(table)
  quoted_column = connection.quote_column_name(column)
  rows = connection.select_rows(
    "SELECT id, #{quoted_column} FROM public.#{quoted_table} WHERE #{quoted_column} IS NOT NULL ORDER BY id"
  )
  rows.map do |id, ciphertext|
    plaintext =
      begin
        type.deserialize(ciphertext)
      rescue StandardError => e
        abort "decrypt_columns.rb: #{table}.#{column} id=#{id} cannot be decrypted on the #{side} side (#{e.class})"
      end
    "UPDATE public.#{quoted_table} SET #{quoted_column} = " \
      "convert_from(decode('#{Base64.strict_encode64(plaintext)}', 'base64'), 'UTF8') WHERE id = #{Integer(id)};\n"
  end
end

File.write(out, statements.join)
