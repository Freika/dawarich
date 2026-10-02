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

    with {:ok, [count, ttl]} when is_integer(count) and is_integer(ttl) <-
           Redix.pipeline(redis, [["INCRBY", key, "1"], ["TTL", key]], timeout: 5_000),
         {:ok, _} <- expire(redis, key, ttl, now) do
      {:ok, count}
    else
      _ -> :error
    end
  catch
    :exit, _ -> :error
  end

  defp expire(_redis, _key, ttl, _now) when ttl >= 0, do: {:ok, ttl}

  defp expire(redis, key, _ttl, now),
    do: Redix.command(redis, ["EXPIRE", key, "#{@period - rem(now, @period) + 1}"])

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

      Enum.any?(
        ~w(locale format),
        &(Map.has_key?(params, &1) and not Map.has_key?(conn.assigns.api_query, &1))
      ) ->
        {:replay, "body locale or format"}

      not (is_binary(params["phrase"]) or is_nil(params["phrase"])) ->
        {:replay, "phrase shape"}

      true ->
        :ok
    end
  end

  defp throttle(conn, now) do
    case count(key(Headers.peer(conn.remote_ip), conn.path_params["id"], now), now) do
      {:ok, count} when count > @limit -> throttled(conn, now)
      {:ok, _count} -> conn
      :error -> Body.replay(conn, "rack-attack store")
    end
  end

  defp throttled(conn, now) do
    %{conn | resp_headers: []}
    |> put_resp_header("content-type", "application/json")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("retry-after", Integer.to_string(@period - rem(now, @period)))
    |> Map.update!(:resp_headers, &(&1 ++ [{"cache-control", "no-cache"}]))
    |> send_resp(429, @body)
    |> halt()
  end
end
