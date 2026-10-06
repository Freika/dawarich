defmodule Dawarich.Tiles.Http do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Entitlements, RailsTime, Redis, Repo, RubyInteger}
  alias DawarichWeb.Api.Params

  def coords(params) do
    with {z, ""} <- Integer.parse(to_string(params["z"])),
         {x, ""} <- Integer.parse(to_string(params["x"])),
         {y, ""} <- Integer.parse(to_string(params["y"])),
         true <-
           z in 0..22 and x >= 0 and y >= 0 and x < Integer.pow(2, z) and y < Integer.pow(2, z) do
      {:ok, {z, x, y}}
    else
      _ -> {:error, 400, "Invalid tile coordinates"}
    end
  end

  def range(user, params) do
    if present?(params["start_at"]) or present?(params["end_at"]) do
      RailsTime.with_zone(user.timezone, fn ->
        with {:ok, from} <- timestamp(params["start_at"]),
             {:ok, to} <- timestamp(params["end_at"]),
             true <- from <= to do
          {:ok, {from, to}}
        else
          _ -> {:error, 400, "Both start_at and end_at must be present and parsable"}
        end
      end)
    else
      {:ok, nil}
    end
  end

  def timestamp(value) do
    with {:ok, stamp} <- Params.timestamp(value) do
      {from, _} = Dawarich.SafeTimestamp.range(stamp, nil, DateTime.utc_now())
      {:ok, from}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def strict_timestamp(value) do
    with {:ok, stamp} <- Params.timestamp(value) do
      case stamp do
        {:epoch, n} ->
          {:ok, n}

        {:text, text} ->
          [[n]] =
            Repo.query!("SELECT floor(extract(epoch FROM $1::text::timestamptz))::bigint", [text]).rows

          {:ok, n}
      end
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def window(user) do
    if Entitlements.full_access?(
         user,
         System.get_env("SELF_HOSTED") != "false",
         DateTime.utc_now()
       ) do
      nil
    else
      RailsTime.with_zone(user.timezone, fn ->
        [[n]] =
          Repo.query!(
            "SELECT floor(extract(epoch FROM CURRENT_TIMESTAMP - interval '12 months'))::bigint"
          ).rows

        n
      end)
    end
  end

  def point_scope(user, params, range) do
    {where, args} = {"p.user_id = $1", [user.id]}
    {where, args} = bound(where, args, "p.timestamp", window(user))

    {where, args} =
      if range,
        do:
          {where <> " AND p.timestamp BETWEEN $#{length(args) + 1} AND $#{length(args) + 2}",
           args ++ Tuple.to_list(range)},
        else: {where, args}

    if present?(params["import_id"]),
      do:
        {where <> " AND p.import_id = $#{length(args) + 1}",
         args ++ [RubyInteger.to_i(params["import_id"])]},
      else: {where, args}
  end

  def bound(where, args, _column, nil), do: {where, args}

  def bound(where, args, column, n),
    do: {where <> " AND #{column} >= $#{length(args) + 1}", args ++ [n]}

  def present?(v), do: is_binary(v) and String.trim(v) != ""

  def query(sql, args) do
    Repo.transaction(fn ->
      timeout =
        System.get_env("VECTOR_TILES_QUERY_TIMEOUT_MS", "5000") |> RubyInteger.to_i() |> max(1)

      Repo.query!("SET LOCAL statement_timeout = #{timeout}")
      Repo.query!(sql, args).rows
    end)
    |> case do
      {:ok, rows} -> rows
      {:error, error} -> raise error
    end
  end

  def epoch(layer, id, {from, to}) do
    years =
      (DateTime.from_unix!(from).year |> max(1970) |> min(2100))..(DateTime.from_unix!(to).year
                                                                   |> max(1970)
                                                                   |> min(2100))

    Enum.map_join(Enum.to_list(years) ++ ["all"], "-", fn year ->
      key = "#{layer}:tile_epoch:#{id}:#{year}"

      case Redis.cache_command(["GET", key]) do
        {:ok, value} when is_binary(value) ->
          value

        _ ->
          token = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
          Redis.cache_command(["SET", key, token])
          token
      end
    end)
  end

  def etag(parts) do
    key =
      parts |> List.flatten() |> Enum.map_join("/", &if(is_nil(&1), do: "", else: to_string(&1)))

    prefix = System.get_env("RAILS_CACHE_ID") || System.get_env("RAILS_APP_VERSION")
    key = if prefix, do: prefix <> "/" <> key, else: key
    ~s(W/"#{:crypto.hash(:sha256, key) |> Base.encode16(case: :lower) |> binary_part(0, 32)}")
  end

  def call(conn, layer, module, schema) do
    user = conn.assigns.api_user
    params = Map.merge(conn.assigns.api_params, conn.path_params)
    conn = put_resp_header(conn, "vary", "Authorization")

    with {:ok, range} <- range(user, params) do
      etag = if range, do: tile_etag(user, params, range, layer, schema)
      conn = if etag, do: put_resp_header(conn, "etag", etag), else: conn
      cache = if range, do: "max-age=300, private", else: "no-store"
      conn = put_resp_header(conn, "cache-control", cache)

      if etag &&
           Dawarich.MapApi.Cache.fresh?(get_req_header(conn, "if-none-match"), etag, nil, nil) do
        send_resp(conn, 304, "")
      else
        case module.fetch(user, params) do
          {:ok, "", _} ->
            send_resp(conn, 204, "")

          {:ok, tile, _} ->
            conn
            |> put_resp_header("content-type", "application/vnd.mapbox-vector-tile")
            |> put_resp_header("content-disposition", "inline")
            |> put_resp_header("content-transfer-encoding", "binary")
            |> send_resp(200, tile)

          {:error, status, message} ->
            error(conn, status, message)
        end
      end
    else
      {:error, status, message} -> error(conn, status, message)
      _ -> error(conn, 500, "Tile query failed")
    end
  rescue
    error ->
      error(
        conn,
        if(match?(%Postgrex.Error{postgres: %{code: :query_canceled}}, error), do: 503, else: 500),
        if(match?(%Postgrex.Error{postgres: %{code: :query_canceled}}, error),
          do: "Tile query timed out",
          else: "Tile query failed"
        )
      )
  end

  def error(conn, status, message) do
    conn
    |> delete_resp_header("etag")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: message}))
  end

  defp tile_etag(user, params, range, layer, schema) do
    epochs =
      if layer == "tracks",
        do: [epoch("tracks", user.id, range), epoch("points", user.id, range)],
        else: epoch("points", user.id, range)

    cutoff = window(user)
    date = if cutoff, do: cutoff |> DateTime.from_unix!() |> DateTime.to_date()

    etag([
      schema,
      user.id,
      epochs,
      date,
      params["z"],
      params["x"],
      params["y"],
      Tuple.to_list(range),
      params["import_id"]
    ])
  end
end
