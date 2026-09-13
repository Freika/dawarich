# frozen_string_literal: true

module RuboCop
  module Cop
    module Dawarich
      class PointsLatLonAccess < Base
        MSG_QUERY = 'Avoid querying `:latitude`/`:longitude` on the `points` table — those columns ' \
                    'are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use ' \
                    '`ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying ' \
                    '`Place` or `Area`.'
        MSG_READER = '`Point#latitude`/`Point#longitude` read legacy nil columns. Use `Point#lat`/`Point#lon`.'

        QUERY_METHODS = %i[
          pluck pick select where order group find_by find_or_create_by update_all update_columns
        ].to_set.freeze

        LAT_LON = %i[latitude longitude].to_set.freeze

        def on_send(node)
          check_query_symbols(node) if QUERY_METHODS.include?(node.method_name) && node.receiver
          check_reader_call(node)   if LAT_LON.include?(node.method_name) && node.receiver
        end

        private

        def check_query_symbols(node)
          node.arguments.each do |arg|
            case arg.type
            when :sym
              add_offense(arg, message: MSG_QUERY) if LAT_LON.include?(arg.value)
            when :hash
              next unless node.method?(:where)

              arg.pairs.each do |pair|
                key = pair.key
                add_offense(pair, message: MSG_QUERY) if key.sym_type? && LAT_LON.include?(key.value)
              end
            end
          end
        end

        def check_reader_call(node)
          receiver = node.receiver
          return unless receiver

          if receiver.lvar_type?
            name = receiver.children.first
            return add_offense(node, message: MSG_READER) if name == :point

            add_offense(node, message: MSG_READER) if in_points_iteration_block?(receiver)
          elsif receiver.send_type? && receiver.method_name == :point && receiver.receiver.nil?
            add_offense(node, message: MSG_READER)
          end
        end

        def in_points_iteration_block?(node)
          block = node.each_ancestor(:block).first
          return false unless block

          send_node = block.send_node
          return false unless send_node

          points_relation?(send_node.receiver)
        end

        def points_relation?(node)
          return false unless node

          case node.type
          when :send
            return true if %i[points scoped_points].include?(node.method_name)

            points_relation?(node.receiver)
          when :const
            node.const_name == 'Point' || node.const_name.to_s.end_with?('::Point')
          when :lvar
            node.children.first == :points
          else
            false
          end
        end
      end
    end
  end
end
