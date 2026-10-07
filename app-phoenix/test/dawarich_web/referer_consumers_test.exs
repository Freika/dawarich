defmodule DawarichWeb.RefererConsumersTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Test.RailsUser

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    RailsUser.insert!(%{
      id: 77441,
      email: "safe-return@example.invalid",
      admin: false,
      settings: %{"locale" => "en"}
    })

    %{user: Dawarich.Accounts.get(77441), session: RailsUser.session(77441)}
  end

  @tag :safe_back3
  test "miscellaneous settings and admin refusal preserve Rails relative and other-port returns",
       ctx do
    for {referer, location} <- [
          {"/settings/general?tab=theme#card",
           "http://www.example.com/settings/general?tab=theme#card"},
          {"https://www.example.com:8443/return?x=1#card",
           "https://www.example.com:8443/return?x=1#card"},
          {"http://user@www.example.com/return", "http://www.example.com/"},
          {"//www.example.com/return", "http://www.example.com/"}
        ] do
      conn =
        Plug.Test.conn(:get, "http://www.example.com/settings/theme?theme=dark")
        |> put_req_header("referer", referer)
        |> assign(:current_user, ctx.user)
        |> assign(:rails_session, ctx.session)
        |> assign(:api_params, %{"theme" => "dark"})

      result = DawarichWeb.SettingsMiscActions.call(conn, :theme)
      assert result.status == 302
      assert get_resp_header(result, "location") == [location]

      refused =
        Plug.Test.conn(:post, "http://www.example.com/admin/settings")
        |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
        |> put_req_header("referer", referer)
        |> DawarichWeb.AdminWrites.Fallback.call(
          action: :instance,
          context: %{self_hosted: true, oidc: false}
        )

      assert refused.status == 303
      assert get_resp_header(refused, "location") == [location]

      assert refused.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] =~
               "not authorized"
    end
  end
end
