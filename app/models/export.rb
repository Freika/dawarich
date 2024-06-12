# frozen_string_literal: true

class Export < ApplicationRecord
  belongs_to :user

  enum status: { created: 0, processing: 1, completed: 2, failed: 3 }

  validates :name, presence: true

  before_destroy :delete_export_file

  private

  def delete_export_file
    file_path = Rails.root.join('public', 'exports', "#{name}.json")

    File.delete(file_path) if File.exist?(file_path)
  end
end
