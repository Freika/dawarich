defmodule DawarichWeb.ExportsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})

    user =
      RailsUser.insert!(%{
        id: 7201,
        email: "a7-exports-live@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: user}
  end

  defp live_as(user, path \\ "/exports"),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  describe "route" do
    test "a signed-in user gets the page under Rails' title", %{user: user} do
      {:ok, _view, html} = live_as(user)
      assert html =~ "<title>Exports | Dawarich</title>"
    end

    test "a signed-out visitor is sent to Rails' sign-in page" do
      assert redirected_to(get(build_conn(), "/exports?page=2"), 302) ==
               "http://www.example.com/users/sign_in"
    end

    test "HEAD answers without a body", %{user: user} do
      conn = head(RailsUser.signed_in(user.id), "/exports")
      assert {conn.status, conn.resp_body} == {200, ""}
    end
  end
end
