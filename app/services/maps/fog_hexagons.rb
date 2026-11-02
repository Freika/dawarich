# frozen_string_literal: true

module Maps
  # Fog and city cards read the same immutable all-history opening ledger.
  # A date range marks first discoveries; it never closes older cells.
  class FogHexagons
    def initialize(user:, start_date:, end_date:, privacy_zone_masker: nil, snapshot_id: nil)
      @user = user
      @start_date = start_date
      @end_date = end_date
      @masker = privacy_zone_masker
      @snapshot_id = snapshot_id
    end

    def call
      state = Exploration::Schedule.call(@user)
      snapshot = if @snapshot_id.present?
                   Exploration::Snapshot.where(user_id: @user.id).where.not(completed_at: nil).find(@snapshot_id)
                 else
                   Exploration::Snapshot.find_by(id: state.snapshot_id, user_id: @user.id)
                 end
      updating = !snapshot || (@snapshot_id.blank? && !state.settled?(snapshot))
      status = if updating && state.failed_at
                 'error'
               elsif updating
                 snapshot ? 'updating' : 'calculating'
               else
                 'ready'
               end
      relation = snapshot ? Exploration::Opening.where(snapshot_id: snapshot.id) : Exploration::Opening.none
      if @masker&.any?
        relation = relation.joins('JOIN exploration_cells ON exploration_cells.id=exploration_openings.cell_id')
                           .where("NOT #{@masker.touches_sql('exploration_cells.geom')}")
      end
      rows = relation.order(:cell_id).pluck(:cell_id, :first_timestamp)
      indexes = rows.map(&:first)
      newly_opened = rows.filter_map { |id, timestamp| id if timestamp.between?(@start_date.to_i, @end_date.to_i) }
      { 'h3_indexes' => indexes, 'new_h3_indexes' => newly_opened,
        'metadata' => { 'count' => indexes.size, 'status' => status, 'snapshot_id' => snapshot&.id,
                        'resolution' => Exploration::CellGeometry::RESOLUTION, 'pinned' => @snapshot_id.present? } }
    end
  end
end
