defmodule Dawarich.JobsCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.ScratchRepo

  @phoenix ~w(job_owners job_outbox_replays processed_commands runtime_nodes app_version supporter_checks trip_events notification_events delivery_claims export_claims rails_commands rails_commands_dead track_generations track_generation_chunks stats_point_counts)
  @oban ~w(oban_jobs oban_peers)

  using do
    quote do
      alias Dawarich.ScratchRepo
      import Dawarich.JobsCase
    end
  end

  setup do
    unless rows("SELECT to_regclass('public.job_outbox') IS NOT NULL") == [[true]] do
      Dawarich.ScratchCase.recreate_public!(ScratchRepo)

      ScratchRepo.query!(Dawarich.ReleaseMigrator.baseline_sql(), [],
        query_type: :text,
        log: false
      )
    end

    ScratchRepo.query!(
      "TRUNCATE public.job_outbox, public.exports, public.users, public.point_sources, public.active_storage_attachments, public.active_storage_blobs, public.family_invitations, public.families CASCADE",
      [],
      log: false
    )

    tables = Enum.map(@phoenix, &("phoenix." <> &1)) ++ Enum.map(@oban, &("oban." <> &1))
    ScratchRepo.query!("TRUNCATE #{Enum.join(tables, ", ")} RESTART IDENTITY", [], log: false)
    :ok
  end

  def rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows

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
