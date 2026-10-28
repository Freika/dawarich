# frozen_string_literal: true

module Exploration
  class Rebuild
    BATCH_SIZE = 2_000

    def initialize(user)
      @user = user
    end

    def call
      State.with_advisory_lock("exploration-user-#{@user.id}", timeout_seconds: 0) do
        @state = State.find_or_create_by!(user_id: @user.id)
        @state.update_column(:activated_at, Time.current) unless @state.activated_at
        @dataset = Geography.current || Geography.install!
        current = Snapshot.find_by(id: @state.snapshot_id)
        if @state.published_revision == @state.revision && current&.dataset_id == @dataset.id &&
           !current.world_opened_area.nil?
          next
        end

        WorldTotals.prepare_dataset!(@dataset)
        @revision = @state.revision
        @snapshot = Snapshot.create!(user_id: @user.id, dataset_id: @dataset.id, revision: @revision)
        # A transaction owns the temporary flight table. Source writes remain
        # free to proceed; revision fencing rejects a result changed underneath us.
        ApplicationRecord.transaction do
          FlightEvidence.prepare!(@user)
          collect_openings
          summarize
          @snapshot.update!(world_opened_area: WorldTotals.opened_area(@snapshot))
        end
        publish
      ensure
        @state&.update_columns(requested_at: nil)
      end
    rescue StandardError
      @state&.update_columns(requested_at: nil, failed_at: Time.current)
      @snapshot&.destroy! unless @state&.reload&.snapshot_id == @snapshot&.id
      raise
    end

    private

    def connection = ApplicationRecord.connection

    def collect_openings
      relation = FlightEvidence.qualifying(@user.points.complete.not_anomaly)
                               .where('timestamp <= ?', Time.current.to_i).reorder(:id)
      last_id = 0
      loop do
        rows = relation.where('points.id > ?', last_id).limit(BATCH_SIZE).pluck(
          :id, :timestamp, Arel.sql('ST_Y(lonlat::geometry)'), Arel.sql('ST_X(lonlat::geometry)')
        )
        break if rows.empty?

        last_id = rows.last.first
        valid = rows.select { |_, _, lat, lon| lat&.between?(-90, 90) && lon&.between?(-180, 180) }
        openings = valid.group_by { |_, _, lat, lon| CellGeometry.id(lat, lon) }.map do |cell_id, evidence|
          id, timestamp = evidence.min_by { |row| [row[1], row[0]] }
          { snapshot_id: @snapshot.id, cell_id: cell_id, first_timestamp: timestamp, point_id: id }
        end
        next if openings.empty?

        Coverage.ensure!(openings.pluck(:cell_id), @dataset)
        Opening.upsert_all(openings, unique_by: %i[snapshot_id cell_id], on_duplicate: Arel.sql(<<~SQL.squish))
          point_id = CASE WHEN (EXCLUDED.first_timestamp,EXCLUDED.point_id) < (exploration_openings.first_timestamp,exploration_openings.point_id)
            THEN EXCLUDED.point_id ELSE exploration_openings.point_id END,
          first_timestamp = LEAST(exploration_openings.first_timestamp,EXCLUDED.first_timestamp)
        SQL
        record_visits(valid.map(&:first))
      end
    end

    def record_visits(point_ids)
      connection.execute(<<~SQL)
        INSERT INTO exploration_country_totals(snapshot_id,territory_id,visited,opened_area)
        SELECT DISTINCT #{@snapshot.id},t.id,true,0 FROM points p JOIN exploration_territories t
          ON t.dataset_id=#{@dataset.id} AND t.boundary && p.lonlat::geometry
          AND ST_Covers(t.boundary,p.lonlat::geometry)
        WHERE p.id IN (#{point_ids.join(',')}) AND p.user_id=#{@user.id}
        ON CONFLICT(snapshot_id,territory_id) DO UPDATE SET visited=true
      SQL
    end

    def summarize
      connection.execute(<<~SQL)
        INSERT INTO exploration_country_totals(snapshot_id,territory_id,opened_area,visited)
        SELECT #{@snapshot.id},a.key::bigint,SUM(a.value::float),false
        FROM exploration_openings o JOIN exploration_cell_coverages c
          ON c.cell_id=o.cell_id AND c.dataset_id=#{@dataset.id}
        CROSS JOIN LATERAL jsonb_each_text(c.areas) a WHERE o.snapshot_id=#{@snapshot.id}
        GROUP BY a.key
        ON CONFLICT(snapshot_id,territory_id) DO UPDATE SET opened_area=EXCLUDED.opened_area
      SQL
    end

    def publish
      @state.with_lock do
        if @state.revision == @revision && Geography.current&.id == @dataset.id
          @snapshot.update!(completed_at: Time.current)
          @state.update!(snapshot_id: @snapshot.id, published_revision: @revision, failed_at: nil)
        else
          @snapshot.destroy!
        end
      end
      # Preserve previous snapshots for in-flight paginated readers.
      Snapshot.where(user_id: @user.id).where.not(id: @state.snapshot_id)
              .where.not(id: @user.achievement_collectibles.where(series: 'city', revoked_at: nil)
                                 .pluck(Arel.sql("(data->>'snapshot_id')::bigint")))
              .where('created_at < ?', 2.hours.ago).delete_all
    end
  end
end
