defmodule Dawarich.JobsCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.ScratchRepo

  @phoenix ~w(upload_receipts cable_events cable_streams job_owners job_outbox_replays processed_commands runtime_nodes app_version supporter_checks trip_events notification_events delivery_claims export_claims rails_commands rails_commands_dead track_generations track_generation_chunks stats_point_counts import_archive_children import_runs import_handoffs import_download_requests import_destroy_runs import_blob_purges release_operations raw_data_archive_chunks once_claims counters epochs leases registration_setting stats_geocoded_days cursors achievement_checks)
  @backfill ~w(track_backfill_ranges track_backfill_walks)
  @oban ~w(oban_jobs oban_peers)

  using opts do
    if opts[:async] && opts[:group] != :scratch_db,
      do: raise(ArgumentError, "async JobsCase modules need group: :scratch_db")

    quote do
      alias Dawarich.ScratchRepo
      import Dawarich.JobsCase
    end
  end

  setup do
    reset!(ScratchRepo)
  end

  def reset!(repo) do
    Dawarich.MapMatchingTasks.await!()
    Dawarich.PublicBaseline.ensure_current!(repo)

    tables =
      ~w(public.job_outbox public.exports public.imports public.pending_imports public.users public.point_sources
         public.active_storage_attachments public.active_storage_blobs public.family_invitations
         public.families public.places public.countries public.instance_settings public.regions) ++
        Enum.map(@phoenix ++ @backfill, &("phoenix." <> &1)) ++ Enum.map(@oban, &("oban." <> &1))

    Dawarich.FixtureCleanup.delete!(repo, tables)
  end

  def rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows

  def hold_lease!(repo, name, holder) do
    repo.query!(
      "INSERT INTO phoenix.leases (name, holder, expires_at) VALUES ($1, $2, statement_timestamp() + interval '60 seconds')",
      [name, holder],
      log: false
    )

    :ok
  end

  def lease_holders(repo, name),
    do: repo.query!("SELECT holder FROM phoenix.leases WHERE name = $1", [name], log: false).rows

  def foreign_lease!(name),
    do:
      rows(
        "INSERT INTO phoenix.leases(name,holder,expires_at) VALUES($1,'rails-holder',now()+interval '1 hour')",
        [name]
      )

  def end_foreign_lease!(name),
    do: rows("DELETE FROM phoenix.leases WHERE name=$1 AND holder='rails-holder'", [name])

  def start_oban(name, opts \\ []) do
    base = [
      name: name,
      repo: ScratchRepo,
      prefix: "oban",
      notifier: Oban.Notifiers.PG,
      testing: :manual
    ]

    ExUnit.Callbacks.start_supervised!({Oban, Keyword.merge(base, opts)}, id: name)
  end

  def outbox!(attrs) do
    row =
      Map.merge(
        %{
          event_id: Ecto.UUID.generate(),
          command_type: "test.echo",
          command_version: 1,
          payload: %{"n" => 1},
          aggregate_id: nil,
          dedupe_key: nil,
          scheduled_at: DateTime.add(DateTime.utc_now(), -1)
        },
        Map.new(attrs)
      )

    rows(
      """
      INSERT INTO public.job_outbox (event_id, command_type, command_version, payload, aggregate_id, dedupe_key, scheduled_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      """,
      [
        Ecto.UUID.dump!(row.event_id),
        row.command_type,
        row.command_version,
        row.payload,
        row.aggregate_id,
        row.dedupe_key,
        row.scheduled_at
      ]
    )

    row.event_id
  end
end
