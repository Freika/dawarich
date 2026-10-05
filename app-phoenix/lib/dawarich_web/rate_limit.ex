defmodule DawarichWeb.RateLimit do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Dawarich.{Accounts, Entitlements, Jobs, State, TtlCache}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{LayoutAssigns, RailsProxy}
  alias DawarichWeb.RateLimit.{Request, Rules}

  @message "API rate limit exceeded. Please wait before making more requests."
  @cors_resource "/api/v1/imports/pending"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{private: %{dawarich_rate_limit: _}} = conn, _opts), do: conn

  def call(conn, _opts) do
    self_hosted = LayoutAssigns.self_hosted?()
    now = System.os_time(:second)

    case decide(conn, %{now: now, plan: &plan/1, repo: Jobs.repo(), self_hosted: self_hosted}) do
      {:pass, conn, counted, token} ->
        conn |> put_private(:dawarich_rate_limit, counted) |> assign(:rate_limit_token, token)

      {:throttled, conn, _counted, data} ->
        throttled(conn, data, now, if(self_hosted, do: nil, else: System.get_env("MANAGER_URL")))

      {:blocked, conn} ->
        blocked(conn)

      {:defer, conn, counted, reason} ->
        Logger.info("[rate_limit] #{conn.request_path} handed to Rails: #{reason}")

        conn
        |> put_private(:dawarich_rate_limit, counted)
        |> RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
        |> halt()
    end
  end

  def decide(conn, opts) do
    facts = Request.facts(conn, opts.self_hosted)
    candidates = Enum.filter(Rules.throttles(), fn rule -> elem(rule, 4).(facts) end)

    cond do
      conn.request_path |> URI.decode() |> Path.expand("/") == @cors_resource ->
        {:defer, conn, [], "Rack CORS resource"}

      candidates == [] and not Rules.blocklist_path?(facts) ->
        {:pass, conn, [], nil}

      true ->
        screen(conn, facts, candidates, opts)
    end
  end

  defp screen(conn, facts, candidates, opts) do
    case Request.screen(conn, facts) do
      {:ok, _, conn} ->
        if Rules.blocked?(facts),
          do: {:blocked, conn},
          else:
            gather(conn, facts, Enum.filter(candidates, &Rules.method?(&1, facts.method)), opts)

      {:defer, reason, conn} ->
        {:defer, conn, [], reason}
    end
  end

  defp gather(conn, facts, applicable, opts) do
    needs = applicable |> Enum.flat_map(&elem(&1, 5)) |> Enum.uniq()

    case Request.inputs(conn, facts, needs) do
      {:ok, inputs, conn} -> count(conn, Map.merge(facts, inputs), applicable, opts)
      {:defer, reason, conn} -> {:defer, conn, [], reason}
    end
  end

  defp count(conn, inputs, applicable, opts) do
    case Rules.evaluate(
           entries(inputs, applicable, opts),
           opts.now,
           &increment(opts.repo, &1, &2)
         ) do
      {:pass, counted, token} -> {:pass, conn, counted, token}
      {:throttled, counted, data} -> {:throttled, conn, counted, data}
      {:defer, counted, reason} -> {:defer, conn, counted, reason}
    end
  rescue
    error -> {:defer, conn, [], "rate limit: " <> inspect(error.__struct__)}
  end

  defp entries(inputs, applicable, opts) do
    token? = Enum.any?(applicable, &(elem(&1, 0) == "api/token"))
    plan = if token? and Ruby.present?(inputs[:api_key]), do: opts.plan.(inputs.api_key)
    inputs = Map.put(inputs, :plan, plan)

    for {name, limit, period, _methods, _path, _needs, key} <- applicable,
        discriminator <- [key.(inputs)],
        discriminator != nil,
        do: {name, Rules.limit(limit, inputs), period, discriminator}
  end

  defp increment(repo, key, ttl) do
    {:ok, State.increment(repo, key, 1, ttl)}
  rescue
    error -> {:error, "counter store: " <> inspect(error.__struct__)}
  end

  def plan(key) do
    TtlCache.fetch(
      {__MODULE__, key},
      120_000,
      fn ->
        with %{} = user <- Accounts.by_api_key(key),
             do: user |> Entitlements.access(false, DateTime.utc_now()) |> elem(1)
      end,
      cache_nil: false
    )
  end

  def release(conn, repo \\ Jobs.repo())

  def release(%{private: %{dawarich_rate_limit: [_ | _] = counted}} = conn, repo) do
    refund(conn, counted, repo)
  end

  def release(conn, _repo), do: conn

  defp refund(conn, [], _repo), do: put_private(conn, :dawarich_rate_limit, [])

  defp refund(conn, [{key, _ttl} | remaining] = counted, repo) do
    result =
      try do
        State.increment(repo, key, -1, 1)
        :ok
      rescue
        error ->
          Logger.warning("event=rate_limit.release_failed reason=#{inspect(error.__struct__)}")
          :error
      end

    case result do
      :ok -> refund(conn, remaining, repo)
      :error -> {:error, put_private(conn, :dawarich_rate_limit, counted)}
    end
  end

  def throttled(conn, %{period: period}, now, manager_url) do
    body =
      Ruby.json(
        {:object,
         [
           {"error", "rate_limit_exceeded"},
           {"message", @message},
           {"upgrade_url", "#{manager_url}/pricing"}
         ]}
      )

    respond(conn, 429, body, [{"retry-after", Integer.to_string(period - rem(now, period))}])
  end

  def blocked(conn) do
    body =
      Ruby.json(
        {:object, [{"error", "payload_too_large"}, {"message", "Request body is too large."}]}
      )

    respond(conn, 413, body, [])
  end

  defp respond(conn, status, body, retry_after) do
    kept =
      Enum.reject(conn.resp_headers, fn {name, _} -> name in ~w(cache-control content-type) end)

    headers =
      kept ++
        [{"content-type", "application/json"}, {"cache-control", "no-store"}] ++
        retry_after ++ [{"cache-control", "no-cache"}]

    %{conn | resp_headers: headers}
    |> send_resp(status, IO.iodata_to_binary(body))
    |> halt()
  end
end
