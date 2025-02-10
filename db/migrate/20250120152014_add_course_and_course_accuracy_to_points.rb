# frozen_string_literal: true

class AddCourseAndCourseAccuracyToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :course, :decimal, precision: 8, scale: 5
    add_column :points, :course_accuracy, :decimal, precision: 8, scale: 5
  end
end
