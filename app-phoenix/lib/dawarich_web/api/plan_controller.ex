defmodule DawarichWeb.Api.PlanController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.{Entitlements, RailsTime}
  alias Dawarich.AccountApi.Closure
  alias DawarichWeb.Api.{Body, Respond}

  @plans %{0 => "lite", 1 => "pro", 2 => "family"}
  @statuses %{nil => nil, 0 => "inactive", 1 => "active", 2 => "trial", 3 => "pending_payment"}
  @sources %{0 => "none", 1 => "paddle", 2 => "apple_iap", 3 => "google_play"}
  @features {:object,
             [
               {"heatmap", true},
               {"fog_of_war", true},
               {"scratch_map", true},
               {"globe_view", true},
               {"integrations", true},
               {"write_api", true},
               {"sharing", true},
               {"full_digest", true},
               {"data_window", nil}
             ]}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :show) do
    result =
      if Dawarich.Standalone.enabled?(),
        do: Closure.plan(conn.assigns.api_user, conn.assigns[:api_now] || DateTime.utc_now()),
        else: fields(conn.assigns.api_user, conn)

    case result do
      {:ok, body} ->
        Respond.json(conn, 200, body)

      {:replay, reason} ->
        if Dawarich.Standalone.enabled?(),
          do: Respond.json(conn, 500, {:object, [{"error", "internal_server_error"}]}),
          else: Body.replay(conn, reason)
    end
  end

  defp fields(user, conn) do
    {full, effective} =
      Entitlements.access(
        user,
        DawarichWeb.LayoutAssigns.self_hosted?(),
        conn.assigns[:api_now] || DateTime.utc_now()
      )

    with {:ok, plan} <- label(@plans, user.plan),
         {:ok, status} <- label(@statuses, user.status),
         {:ok, source} <- label(@sources, user.subscription_source),
         {:ok, until} <- RailsTime.iso8601(user.active_until, user.timezone) do
      {:ok,
       {:object,
        [
          {"plan", plan},
          {"effective_plan", effective},
          {"status", status},
          {"subscription_source", source},
          {"active_until", until},
          {"features", if(full, do: @features, else: lite_features())}
        ]}}
    end
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp lite_features do
    {:object,
     [
       {"heatmap", false},
       {"fog_of_war", false},
       {"scratch_map", false},
       {"globe_view", false},
       {"integrations", false},
       {"write_api", "create_only"},
       {"sharing", false},
       {"full_digest", false},
       {"data_window", "12_months"}
     ]}
  end

  defp label(labels, value) do
    case Map.fetch(labels, value) do
      {:ok, label} -> {:ok, label}
      :error -> {:replay, "enum value #{inspect(value)}"}
    end
  end
end
