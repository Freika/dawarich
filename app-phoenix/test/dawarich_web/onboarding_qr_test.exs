defmodule DawarichWeb.OnboardingQrTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Plug.Conn
  alias Dawarich.Test.RailsUser

  @key "synthetic-onboarding-qr-key"

  setup do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "qr-#{id}@dawarich.test", api_key: @key})
    %{id: id}
  end

  test "routed onboarding QR accepts the owner cookie and refuses anonymous requests", %{id: id} do
    owner =
      Phoenix.ConnTest.dispatch(
        RailsUser.signed_in(id),
        DawarichWeb.Endpoint,
        :get,
        "/settings/onboarding/qr.svg",
        nil
      )

    assert owner.status == 200
    assert get_resp_header(owner, "cache-control") == ["private, no-store"]
    assert get_resp_header(owner, "vary") == ["Cookie"]

    anonymous =
      Phoenix.ConnTest.dispatch(
        Phoenix.ConnTest.build_conn(),
        DawarichWeb.Endpoint,
        :get,
        "/settings/onboarding/qr.svg",
        nil
      )

    assert anonymous.status == 401
  end

  test "onboarding QR is owner-authenticated no-store and never in LiveView state", %{id: id} do
    conn = qr(RailsUser.signed_in(id))
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/svg+xml"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "vary") == ["Cookie"]
    assert conn.resp_body =~ "<svg"
    refute conn.resp_body =~ @key

    anonymous = qr(Phoenix.ConnTest.build_conn())
    assert anonymous.status == 401
    assert get_resp_header(anonymous, "cache-control") == ["private, no-store"]
    refute anonymous.resp_body =~ "<svg"

    assert qr(RailsUser.signed_in(id) |> put_req_header("sec-fetch-site", "cross-site")).status ==
             403

    assert qr(%{RailsUser.signed_in(id) | method: "POST"}).status == 405

    user = Dawarich.Accounts.get(id)
    navbar = Dawarich.Navbar.load(user, now: DateTime.utc_now(), self_hosted: true)

    html =
      render_component(&DawarichWeb.OnboardingModal.onboarding_modal/1,
        current_user: user,
        navbar: navbar,
        locale: "en",
        base_url: "http://localhost",
        rails_csrf_token: "token",
        native: true
      )

    [_, key_qr] =
      Regex.run(~r/<path d="([^"]+)"/, Dawarich.QrSvg.api_key("http://localhost/", @key, 3))

    refute html =~ @key
    refute html =~ key_qr
    assert html =~ ~s(phx-hook="CredentialQr")
    assert html =~ ~s(id="onboarding-api-qr")
    refute html =~ ~s(phx-hook="Onboarding")
  end

  defp qr(conn) do
    conn
    |> Map.put(:path_info, ["settings", "onboarding", "qr.svg"])
    |> Map.put(:request_path, "/settings/onboarding/qr.svg")
    |> DawarichWeb.OnboardingQr.call(DawarichWeb.OnboardingQr.init([]))
  end
end
