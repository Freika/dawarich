# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'FIT developer field name resolution' do
  let(:entity) do
    fit_entity = Fit4Ruby::FitFileEntity.new
    activity = fit_entity.set_type('activity')
    activity.new_developer_data_id(
      application_id: [24, 251, 44, 240, 26, 75, 67, 13, 173, 102, 152, 140, 132, 116, 33, 244],
      application_version: 77
    )
    fit_entity
  end

  def build_field_description
    Fit4Ruby::FieldDescription.new(
      developer_data_index: 0, field_definition_number: 0, fit_base_type_id: 132,
      field_name: 'Power', units: 'Watts', native_mesg_num: 20, native_field_num: 7
    )
  end

  it 'resolves the developer field name when passed the FitFileEntity' do
    expect(build_field_description.full_field_name(entity))
      .to eq('Power_18FB2CF01A4B430DAD66988C847421F4')
  end

  it 'resolves the developer field name when passed the developer_data_ids array' do
    developer_data_ids = entity.top_level_record.developer_data_ids

    expect(build_field_description.full_field_name(developer_data_ids))
      .to eq('Power_18FB2CF01A4B430DAD66988C847421F4')
  end
end
