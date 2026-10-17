defmodule DawarichWeb.Api.ImmichController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.{I18n, ReleaseMigration, SubscriptionToken}
  alias Dawarich.Photos.Enrichment
  alias DawarichWeb.Api.Respond

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    user = conn.assigns.api_user
    now = conn.assigns[:api_now] || DateTime.utc_now()

    if Enrichment.pro?(user, now) do
      case Enrichment.run(action, user, conn.assigns.api_params) do
        {:ok, status, term} ->
          Respond.json(conn, status, Enrichment.term(term))

        {:error, :verification_unavailable} ->
          Respond.json(conn, 503, %{"error" => "verification_unavailable"})

        {:error, status} ->
          Respond.json(conn, status, %{"error" => "Internal Server Error"})
      end
    else
      upgrade =
        if ReleaseMigration.self_hosted?(), do: nil, else: SubscriptionToken.url(user, now)

      Respond.json(
        conn,
        403,
        {:object,
         [
           {"error", "pro_plan_required"},
           {"message", I18n.en!("controllers.api.this_feature_requires_a_pro_plan")},
           {"upgrade_url", upgrade}
         ]}
      )
    end
  end
end
