defmodule DawarichWeb.Api.PlanController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.RailsTime
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
    user = conn.assigns.api_user

    with {:ok, plan} <- label(@plans, user.plan),
         {:ok, status} <- label(@statuses, user.status),
         {:ok, source} <- label(@sources, user.subscription_source),
         {:ok, until} <- RailsTime.iso8601(user.active_until, user.timezone) do
      Respond.json(
        conn,
        200,
        {:object,
         [
           {"plan", plan},
           {"effective_plan", plan},
           {"status", status},
           {"subscription_source", source},
           {"active_until", until},
           {"features", @features}
         ]}
      )
    else
      {:replay, reason} -> Body.replay(conn, reason)
    end
  rescue
    error -> Body.replay(conn, inspect(error.__struct__))
  end

  defp label(labels, value) do
    case Map.fetch(labels, value) do
      {:ok, label} -> {:ok, label}
      :error -> {:replay, "enum value #{inspect(value)}"}
    end
  end
end
