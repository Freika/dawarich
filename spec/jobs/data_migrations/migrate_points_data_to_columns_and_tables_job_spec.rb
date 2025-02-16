# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::MigratePointsDataToColumnsAndTablesJob, type: :job do
  let(:point) { create(:point) }

  it 'migrates point data to columns and tables' do
    expect_any_instance_of(DataMigrations::MigratePoint).to receive(:call)

    described_class.perform_now([point.id])
  end
end
