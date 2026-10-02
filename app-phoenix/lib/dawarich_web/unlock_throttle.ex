defmodule DawarichWeb.UnlockThrottle do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.Api.Body
  alias DawarichWeb.RailsProxy.Headers

  @period 300
  @limit 5
  @body ~s({"error":"rate_limit_exceeded","message":"API rate limit exceeded. Please wait before making more requests.","upgrade_url":"/pricing"})

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case admission(conn) do
      :ok -> throttle(conn, System.os_time(:second))
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  def key(ip, id, now),
    do:
      "rack::attack:#{div(now, @period)}:shared_links/unlock:#{String.downcase(ip <> ":" <> id)}"

  def count(key, now) do
    redis = Dawarich.Redis.rack_attack()

    case Redix.pipeline(redis, [["INCRBY", key, "1"], ["TTL", key]], timeout: 5_000) do
      {:ok, [count, ttl]} when is_integer(count) ->
        if ttl < 0,
          do: Redix.command(redis, ["EXPIRE", key, "#{@period - rem(now, @period) + 1}"])

        count

      _ ->
        1
    end
  catch
    :exit, _ -> 1
  end

  defp admission(conn) do
    params = conn.assigns.api_params

    cond do
      Body.kind(conn) not in [:none, :form] ->
        {:replay, "unlock body type"}

      get_req_header(conn, "x-http-method-override") != [] ->
        {:replay, "method override"}

      Map.has_key?(params, "_method") ->
        {:replay, "method override"}

      Map.has_key?(params, "client") ->
        {:replay, "session-writing parameter"}

      Map.has_key?(params, "locale") and not Map.has_key?(conn.assigns.api_query, "locale") ->
        {:replay, "body locale"}

      not (is_binary(params["phrase"]) or is_nil(params["phrase"])) ->
        {:replay, "phrase shape"}

      true ->
        :ok
    end
  end

  defp throttle(conn, now) do
    ip = Headers.peer(conn.remote_ip)

    if count(key(ip, conn.path_params["id"], now), now) > @limit,
      do:
        %{conn | resp_headers: []}
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("content-type", "application/json")
        |> put_resp_header("retry-after", Integer.to_string(@period - rem(now, @period)))
        |> Map.update!(:resp_headers, &(&1 ++ [{"cache-control", "no-cache"}]))
        |> send_resp(429, @body)
        |> halt(),
      else: conn
  end
end
