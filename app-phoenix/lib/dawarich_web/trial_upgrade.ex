defmodule DawarichWeb.TrialUpgrade do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  require Logger
  alias Dawarich.SubscriptionToken
  alias DawarichWeb.{LayoutAssigns, RequestURL}

  @impl true
  def init(opts), do: opts
  @impl true
  def call(%{halted: true} = conn, _opts), do: conn

  def call(conn, opts) do
    conn = DawarichWeb.TrialHomeSession.call(conn, [])

    if Map.get_lazy(conn.assigns, :self_hosted, &LayoutAssigns.self_hosted?/0) do
      redirect(conn, RequestURL.base(conn) <> "/")
    else
      if Dawarich.Standalone.enabled?() and not DawarichWeb.TrialGate.checkout_configured?() do
        DawarichWeb.StandaloneError.respond(conn, "checkout_unavailable", 503)
      else
        user = conn.assigns.current_user
        query = Plug.Conn.Query.decode(conn.query_string)
        plan = sanitize(query["plan"], ~w(pro lite))
        interval = sanitize(query["interval"], ~w(annual monthly))
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        jti = Keyword.get_lazy(opts, :jti, &Ecto.UUID.generate/0)
        token = SubscriptionToken.generate(user, now, jti, plan: plan, interval: interval)

        Logger.info(fn ->
          Jason.encode!(
            Jason.OrderedObject.new([
              {"event", "trial_upgrades_viewed"},
              {"user_id", user.id},
              {"plan", plan},
              {"interval", interval}
            ])
          )
        end)

        redirect(conn, System.fetch_env!("MANAGER_URL") <> "/auth/dawarich?token=" <> token)
      end
    end
  end

  defp sanitize(value, allowed), do: if(value in allowed, do: value)

  defp redirect(conn, location) do
    conn
    |> put_resp_header("location", location)
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
