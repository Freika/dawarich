# frozen_string_literal: true

require 'rails_helper'

# Regression: the user-data archive importer must not trust archive-supplied
# foreign keys on points, and the exporter must only join same-owner relations,
# so a tampered archive cannot make the importer's own export disclose another
# tenant's visits, places or imports.
RSpec.describe 'Archive points foreign keys are not trusted' do
  describe 'import strips raw identity/foreign keys' do
    let(:user) { create(:user) }

    it 'drops archive-supplied id/visit_id/import_id/track_id/raw_data_archive_id' do
      importer = Users::ImportData::Points.new(user)
      attrs = importer.send(:prepare_point_attributes, {
                              'timestamp' => 1_700_000_000,
                              'lonlat' => 'POINT(1 1)',
                              'id' => 424_242,
                              'visit_id' => 999_999,
                              'import_id' => 888_888,
                              'track_id' => 777_777,
                              'raw_data_archive_id' => 666_666
                            })

      expect(attrs[:user_id]).to eq(user.id)
      expect(attrs[:id]).to be_nil
      expect(attrs[:visit_id]).to be_nil
      expect(attrs[:import_id]).to be_nil
      expect(attrs[:track_id]).to be_nil
      expect(attrs[:raw_data_archive_id]).to be_nil
    end
  end

  describe 'export only joins same-owner relations' do
    let(:attacker) { create(:user) }
    let(:victim) { create(:user) }
    let(:victim_place) { create(:place, user: victim, name: 'VICTIM_PLACE') }
    let(:victim_visit) { create(:visit, user: victim, place: victim_place, name: 'VICTIM_VISIT') }
    let(:victim_import) { create(:import, user: victim, name: 'VICTIM_IMPORT', source: :gpx) }

    it 'does not leak a cross-tenant visit or import referenced by a point' do
      point = create(:point, user: attacker, lonlat: 'POINT(2 2)', timestamp: 1_700_000_001)
      # Simulate the tampered state: attacker point carries the victim's FKs.
      point.update_columns(visit_id: victim_visit.id, import_id: victim_import.id)

      exported = Users::ExportData::Points.new(attacker).call
      row = exported.find { |p| p['timestamp'] == 1_700_000_001 }

      expect(row).to be_present
      expect(row['visit_reference']).to be_nil
      expect(row['import_reference']).to be_nil
      expect(exported.to_json).not_to include('VICTIM')
    end
  end
end
