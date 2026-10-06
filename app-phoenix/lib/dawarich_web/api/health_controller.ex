defmodule DawarichWeb.Api.HealthController do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  alias Dawarich.{I18n, Jobs.Health, Mail.Wave2}
  alias DawarichWeb.Api.{Auth, Headers, Respond}
  alias DawarichWeb.LayoutAssigns

  def init(action), do: action

  def call(conn, :ready) do
    conn = Auth.public(conn)

    if conn.halted do
      conn
    else
      case Dawarich.Readiness.check(conn.assigns[:readiness_opts] || []) do
        :ready -> Respond.json(conn, 200, {:object, [{"status", "ok"}]})
        {:unavailable, _} -> Respond.json(conn, 503, {:object, [{"status", "unavailable"}]})
      end
    end
  end

  def call(conn, :index) do
    conn = Auth.public(conn)

    cond do
      conn.halted -> conn
      conn.assigns.api_user && conn.assigns.api_user.status == 3 -> payment(conn)
      true -> index(conn)
    end
  end

  defp index(conn) do
    summary = Health.summary()

    conn
    |> merge_resp_headers(
      Headers.rate_limit(%{
        self_hosted: LayoutAssigns.self_hosted?(),
        authenticated: conn.assigns.api_user != nil,
        throttle: conn.assigns[:rate_limit_token],
        now: DateTime.to_unix(conn.assigns[:api_now] || DateTime.utc_now())
      })
    )
    |> Respond.json(
      200,
      {:object,
       [
         {"status", "ok"},
         {"phoenix", {:object, [{"status", summary["status"]}, {"alarm", summary["alarm"]}]}}
       ]}
    )
  end

  defp payment(conn) do
    Respond.json(
      conn,
      402,
      {:object,
       [
         {"error", "payment_required"},
         {"message", I18n.en!("controllers.api.complete_your_subscription_to_continue")},
         {"resume_url", resume_url(conn)}
       ]}
    )
  end

  defp resume_url(conn) do
    unless LayoutAssigns.self_hosted?() do
      user = conn.assigns.api_user

      token =
        Wave2.subscription_token(
          user.id,
          user.email,
          System.fetch_env!("JWT_SECRET_KEY"),
          DateTime.to_unix(conn.assigns[:api_now] || DateTime.utc_now())
        )

      "#{System.get_env("MANAGER_URL")}/auth/dawarich?token=#{token}"
    end
  end
end
