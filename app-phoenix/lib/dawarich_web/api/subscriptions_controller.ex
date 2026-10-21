defmodule DawarichWeb.Api.SubscriptionsController do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.AuthApi.{Input, Response}
  alias DawarichWeb.AuthMobile.Http
  def init(opts), do: opts

  def call(conn, opts) do
    conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
    conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])

    if conn.halted do
      conn
    else
      conn = Http.frame(conn)
      context = Keyword.get(opts, :context, %{})

      context =
        Map.put_new(
          context,
          :self_hosted,
          Dawarich.ReleaseMigration.self_hosted?(Map.get_lazy(context, :env, &System.get_env/0))
        )

      with {:ok, params, conn} <- Input.native(conn) do
        result =
          Dawarich.Subscriptions.Callback.call(
            params["token"],
            List.first(get_req_header(conn, "x-webhook-secret")),
            context
          )

        case result do
          {:message, status, key} ->
            message = DawarichWeb.Translate.t(Map.get(context, :locale, "en"), key, %{})
            Response.reply(conn, status, {:object, [{"message", message}]})

          other ->
            Response.result(conn, other, context)
        end
      else
        {:error, conn} -> Response.reply(conn, 400, {:object, [{"error", "invalid_request"}]})
      end
    end
  rescue
    _ ->
      Response.reply(
        Http.frame(conn),
        503,
        {:object, [{"error", "subscription_update_unavailable"}]}
      )
  end
end
