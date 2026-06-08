# frozen_string_literal: true

module Points
  module Archival
    class Serializer
      LONLAT = 'lonlat'

      def self.columns
        @columns ||= Point.column_names
      end

      def self.scalar_columns
        @scalar_columns ||= columns - [LONLAT]
      end

      def self.jsonb_columns
        @jsonb_columns ||= Point.columns_hash.select { |_, c| c.sql_type == 'jsonb' }.keys
      end

      def self.array_columns
        @array_columns ||= Point.columns_hash.select { |_, c| c.array? }.keys
      end

      def self.dump(point)
        attrs = point.attributes_before_type_cast.slice(*scalar_columns)
        array_columns.each { |col| attrs[col] = point.public_send(col) if attrs.key?(col) }
        attrs[LONLAT] = point.has_attribute?('lonlat_ewkb_hex') ? point['lonlat_ewkb_hex'] : ewkb_hex(point.id)
        "#{attrs.to_json}\n"
      end

      def self.ewkb_hex(point_id)
        Point.connection.select_value(
          Point.sanitize_sql_array(
            ["SELECT encode(ST_AsEWKB(lonlat::geometry), 'hex') FROM points WHERE id = ?", point_id]
          )
        )
      end

      def self.parse(line)
        JSON.parse(line)
      end

      def self.insert_sql(rows)
        cols = columns
        col_list = cols.map { |c| Point.connection.quote_column_name(c) }.join(', ')
        values = rows.map { |attrs| value_tuple(attrs, cols) }.join(', ')
        <<~SQL.squish
          INSERT INTO points (#{col_list}) VALUES #{values}
          ON CONFLICT DO NOTHING
        SQL
      end

      def self.value_tuple(attrs, cols)
        rendered = cols.map do |col|
          val = attrs[col]
          if col == LONLAT
            val ? "ST_GeomFromEWKB(decode(#{Point.connection.quote(val)}, 'hex'))" : 'NULL'
          elsif jsonb_columns.include?(col)
            if val.nil?
              'NULL'
            else
              json_str = val.is_a?(String) ? val : val.to_json
              "#{Point.connection.quote(json_str)}::jsonb"
            end
          elsif array_columns.include?(col)
            if val.nil?
              'NULL'
            elsif Array(val).empty?
              "'{}'::text[]"
            else
              "ARRAY[#{Array(val).map { |e| Point.connection.quote(e) }.join(', ')}]::text[]"
            end
          else
            Point.connection.quote(val)
          end
        end
        "(#{rendered.join(', ')})"
      end
    end
  end
end
