defmodule Dawarich.Imports.Trek.Sync do
  @moduledoc false
  alias Dawarich.Imports.Trek.{Client, Payload, Records}
  alias Dawarich.Imports.ZonePeriod

  @empty %{
    "created" => 0,
    "updated" => 0,
    "unchanged" => 0,
    "stopped" => 0,
    "more" => false,
    "next_cursor" => nil
  }

  def context(repo, id, opts \\ []) do
    case repo.query!(
           "SELECT s.user_id,s.base_url,s.api_key,s.selection_token,s.importing,s.status,u.settings FROM trip_sources s JOIN users u ON u.id=s.user_id WHERE s.id=$1 AND u.deleted_at IS NULL",
           [id],
           log: false
         ).rows do
      [[user, url, key, token, importing, status, settings]] ->
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

        %{
          repo: repo,
          id: id,
          user_id: user,
          base_url: url,
          api_key: key,
          selection_token: token,
          importing: importing,
          status: status,
          settings: settings,
          now: now,
          zone:
            ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(settings["timezone"] || "Etc/UTC")),
          opts: opts
        }

      _ ->
        nil
    end
  end

  def import(repo, source, identifier, opts \\ []) do
    import_context(context(repo, source, opts), identifier)
  end

  defp import_context(nil, _), do: {:cancel, :source_missing}

  defp import_context(ctx, identifier) do
    with {:ok, payload} <- Client.trip(client(ctx), identifier) do
      case ctx.repo.transaction(fn ->
             current!(ctx)
             import_payload!(ctx, identifier, payload)
           end) do
        {:ok, result} -> {:ok, result}
        {:error, :lost} -> {:cancel, :ownership_lost}
      end
    else
      {:error, error} ->
        record_error(ctx, error)
        {:error, error}
    end
  rescue
    e in Client.Error ->
      if e.kind != :undated, do: record_error(ctx, e)
      {:error, e}
  end

  def import_payload!(ctx, identifier, payload) do
    normalized = Payload.normalize(payload)
    trip = Records.find(ctx, identifier)
    created = is_nil(trip)
    {id, changed} = Records.synchronize!(ctx, trip, identifier, normalized)
    Records.calculate!(ctx, id, changed)
    update_source!(ctx, %{last_synced_at: DateTime.to_naive(ctx.now), last_error: nil})
    %{id: id, created: created, changed: changed}
  end

  def call(repo, source, opts \\ []) do
    call_context(context(repo, source, opts), opts)
  end

  defp call_context(nil, _), do: {:cancel, :source_missing}

  defp call_context(ctx, opts) do
    repo = ctx.repo
    source = ctx.id

    with {:ok, remote} <- Client.trips(client(ctx)) do
      remote = Map.new(remote, &{to_string(&1["id"]), &1})
      limit = Keyword.get(opts, :limit, 2_147_483_647)
      after_id = Keyword.get(opts, :after_id, 0) || 0

      trips =
        repo.query!(
          "SELECT id,source_identifier FROM trips WHERE trip_source_id=$1 AND user_id=$2 AND source_status=0 AND id>$3 ORDER BY id LIMIT $4",
          [source, ctx.user_id, after_id, limit],
          log: false
        ).rows

      {result, error} =
        Enum.reduce(trips, {@empty, nil}, fn [id, identifier], {result, error} ->
          result = Map.put(result, "next_cursor", id)

          case remote[identifier] do
            value when is_nil(value) ->
              {stop(ctx, id, result), error}

            value ->
              if value["archived"] not in [nil, false] do
                {stop(ctx, id, result), error}
              else
                case sync_trip(ctx, id, identifier) do
                  {:ok, nil} ->
                    {result, error}

                  {:ok, changed} ->
                    {Map.update!(
                       result,
                       if(changed, do: "updated", else: "unchanged"),
                       &(&1 + 1)
                     ), error}

                  {:error, e} when e.kind in [:undated, :invalid_payload] or e.status == 404 ->
                    {stop(ctx, id, result), e.message}

                  {:error, e} ->
                    raise e
                end
              end
          end
        end)

      more =
        opts[:limit] != nil and
          repo.query!(
            "SELECT 1 FROM trips WHERE trip_source_id=$1 AND user_id=$2 AND source_status=0 AND id>$3 LIMIT 1",
            [source, ctx.user_id, result["next_cursor"] || after_id],
            log: false
          ).rows != []

      result = Map.put(result, "more", more)

      case repo.transaction(fn ->
             current!(ctx)

             unless more,
               do:
                 update_source!(ctx, %{
                   last_synced_at: DateTime.to_naive(ctx.now),
                   last_error: error
                 })
           end) do
        {:ok, _} -> {:ok, result}
        {:error, :lost} -> {:cancel, :ownership_lost}
      end
    else
      {:error, error} ->
        record_error(ctx, error)
        {:error, error}
    end
  rescue
    e in Client.Error ->
      record_error(ctx, e)
      {:error, e}
  end

  def current!(ctx) do
    if fence = ctx.opts[:fence], do: fence.()
    ctx.repo.query!("SELECT id FROM trip_sources WHERE id=$1 FOR UPDATE", [ctx.id], log: false)
    current = context(ctx.repo, ctx.id, ctx.opts)

    if is_nil(current) or
         {current.user_id, current.base_url, current.api_key, current.selection_token,
          current.importing,
          current.status} !=
           {ctx.user_id, ctx.base_url, ctx.api_key, ctx.selection_token, ctx.importing,
            ctx.status},
       do: ctx.repo.rollback(:lost)

    :ok
  end

  def record_error(nil, _), do: :ok

  def record_error(ctx, error) do
    if ctx.opts[:record_errors?] != false do
      ctx.repo.transaction(fn ->
        current!(ctx)
        attrs = %{last_error: error.message}
        attrs = if error.status == 401, do: Map.put(attrs, :status, 1), else: attrs
        update_source!(ctx, attrs)
      end)
    end
  end

  def update_source!(ctx, attrs) do
    sets = attrs |> Map.keys() |> Enum.sort()
    sql = Enum.with_index(sets, 2) |> Enum.map_join(",", fn {key, i} -> "#{key}=$#{i}" end)

    ctx.repo.query!(
      "UPDATE trip_sources SET #{sql},updated_at=$#{length(sets) + 2} WHERE id=$1",
      [ctx.id] ++ Enum.map(sets, &attrs[&1]) ++ [DateTime.to_naive(ctx.now)],
      log: false
    )
  end

  defp sync_trip(ctx, id, identifier) do
    with {:ok, payload} <- Client.trip(client(ctx), identifier) do
      case ctx.repo.transaction(fn ->
             current!(ctx)

             case Records.find(ctx, identifier) do
               %{status: 0} = trip when not ctx.importing ->
                 {_id, changed} =
                   Records.synchronize!(ctx, trip, identifier, Payload.normalize(payload))

                 Records.calculate!(ctx, id, changed)
                 changed

               _ ->
                 nil
             end
           end) do
        {:ok, changed} -> {:ok, changed}
        {:error, :lost} -> {:ok, nil}
      end
    end
  rescue
    e in Client.Error -> {:error, e}
  end

  defp stop(ctx, id, result) do
    case ctx.repo.transaction(fn ->
           current!(ctx)

           if ctx.importing,
             do: :skip,
             else:
               ctx.repo.query!(
                 "UPDATE trips SET source_status=1,source_synced_at=$3,updated_at=$3 WHERE id=$1 AND user_id=$2 AND source_status=0 RETURNING id",
                 [id, ctx.user_id, DateTime.to_naive(ctx.now)],
                 log: false
               ).rows
         end) do
      {:ok, [[^id]]} -> Map.update!(result, "stopped", &(&1 + 1))
      _ -> result
    end
  end

  defp client(ctx), do: Client.new(ctx, [encrypted?: true] ++ ctx.opts)
end
