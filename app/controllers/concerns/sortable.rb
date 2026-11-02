# frozen_string_literal: true

module Sortable
  extend ActiveSupport::Concern

  private

  def sorted(scope)
    if sort_column == 'byte_size'
      scope.joins(file_attachment: :blob)
           .order(Arel.sql('active_storage_blobs.byte_size').public_send(sort_direction))
    else
      scope.order(sort_column => sort_direction)
    end
  end

  def sort_column
    self.class::SORTABLE_COLUMNS.include?(params[:sort_by]) ? params[:sort_by] : 'created_at'
  end

  def sort_direction
    params[:order_by] == 'asc' ? :asc : :desc
  end
end
