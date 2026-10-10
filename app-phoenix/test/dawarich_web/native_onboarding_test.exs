defmodule DawarichWeb.NativeOnboardingTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Plug.Conn

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @endpoint DawarichWeb.Endpoint

  defp onboarding_user! do
    RailsUser.insert!(%{
      id: System.unique_integer([:positive]),
      email: "native-onboarding-#{System.unique_integer([:positive])}@example.invalid"
    })
  end

  defp modal(user, token, extra \\ %{}) do
    user = Dawarich.Accounts.get(user.id)
    navbar = Dawarich.Navbar.load(user, now: DateTime.utc_now(), self_hosted: true)

    render_component(&DawarichWeb.OnboardingModal.onboarding_modal/1,
      current_user: user,
      navbar: Map.merge(navbar, extra),
      locale: "en",
      base_url: "http://localhost",
      rails_csrf_token: token,
      native: true
    )
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp fields(form) do
    form
    |> LazyHTML.query("input[type=hidden]")
    |> Enum.map(&{hd(LazyHTML.attribute(&1, "name")), hd(LazyHTML.attribute(&1, "value"))})
  end

  test "the native demo-data form loads demo data and lands on the map" do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    Dawarich.Seeds.Countries.run(Repo)
    user = onboarding_user!()
    session = RailsUser.session(user.id)

    form =
      query(
        modal(user, RailsCsrf.masked_token(session)),
        "form[action='/settings/onboarding/demo_data']"
      )

    body = URI.encode_query(fields(form))

    response =
      build_conn()
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> dispatch(@endpoint, :post, "/settings/onboarding/demo_data", body)

    assert response.status == 302
    assert URI.parse(hd(get_resp_header(response, "location"))).path == "/map/v2"

    assert Dawarich.Test.RailsFormRequests.rails_session(response)["flash"]["flashes"]["notice"] =~
             "Demo"
  end

  test "the native modal uses no Stimulus, links the import step and closes without a request" do
    html = modal(onboarding_user!(), "token")

    assert query(html, "[data-controller], [data-action], [data-upload-target]") |> Enum.empty?()
    refute html =~ "direct_uploads"
    assert query(html, "a[href='/imports/new']") |> Enum.count() >= 1
    assert query(html, "dialog#getting_started form[method=dialog] button") |> Enum.count() >= 1
  end

  test "an account that already has demo data cannot load it again" do
    user = onboarding_user!()
    html = modal(user, "token", %{imports: %{count: 1, demo: true}})

    assert query(html, "form[action='/settings/onboarding/demo_data'] button[disabled]")
           |> Enum.count() == 1
  end
end
