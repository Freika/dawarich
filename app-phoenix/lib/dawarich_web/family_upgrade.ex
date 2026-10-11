defmodule DawarichWeb.FamilyUpgrade do
  @moduledoc false
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    scope = Dawarich.Accounts.Scope.for_user(conn.assigns.current_user, conn.assigns.locale)

    with {:ok, user, ctx} <- Dawarich.Families.NativeReads.actor(scope, []),
         {:ok, %{state: state} = page} when state in [:upgrade, :lapsed] <-
           Dawarich.Families.page(scope, :new),
         true <- state == :upgrade or page.owner? do
      content = if state == :upgrade, do: "create_family", else: "renew_family"

      url =
        Dawarich.SubscriptionToken.url(user, ctx.now, plan: "family", interval: "annual") <>
          "&" <>
          DawarichWeb.Params.to_query(%{
            "utm_source" => "app",
            "utm_medium" => "family",
            "utm_campaign" => "family_upgrade",
            "utm_content" => content
          })

      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("location", url)
      |> send_resp(302, "")
      |> halt()
    else
      _ -> conn |> send_resp(404, "") |> halt()
    end
  end
end
