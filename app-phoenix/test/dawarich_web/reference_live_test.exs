defmodule DawarichWeb.ReferenceLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2, put_private: 3]

  @endpoint DawarichWeb.Endpoint
  @fixture "test/fixtures/rails_cookies.json" |> File.read!() |> Jason.decode!()
  @user @fixture["user"]

  @layout_headers "test/fixtures/layout/self_hosted_dark_en.json"
                  |> File.read!()
                  |> Jason.decode!()
                  |> Map.fetch!("headers")

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    stamp = NaiveDateTime.utc_now()

    Dawarich.Repo.insert_all("users", [
      %{
        id: @user["id"],
        email: @user["email"],
        encrypted_password: @user["encrypted_password"],
        created_at: stamp,
        updated_at: stamp
      }
    ])

    :ok
  end

  defp signed_in,
    do: build_conn() |> put_req_cookie("_dawarich_session", @fixture["session_cookie"])

  defp connecting_as(conn, rails_user_id),
    do:
      put_private(conn, :live_view_connect_info, %{session: %{"rails_user_id" => rails_user_id}})

  test "the Rails user sees the page, with the shared layout, and events work" do
    {:ok, view, html} = live(signed_in() |> connecting_as(@user["id"]), "/phoenix/reference")

    assert html =~ @user["email"]
    assert html =~ ~s(data-theme="dawarich-dark")
    assert view |> element("#reference-bump") |> render_click() =~ ">1<"
  end

  test "Phoenix pages send the security headers Rails pages send, and no others" do
    conn = get(signed_in(), "/phoenix/reference")

    for {name, value} <- @layout_headers,
        do: assert(get_resp_header(conn, name) == List.wrap(value))

    assert get_resp_header(conn, "content-security-policy") == []
  end

  test "a visitor without a Rails session is anonymous" do
    {:ok, _view, html} = live(build_conn() |> connecting_as(nil), "/phoenix/reference")
    refute html =~ @user["email"]
  end

  test "a LiveView whose Rails session ended since the page was rendered redirects on connect" do
    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             live(signed_in() |> connecting_as(nil), "/phoenix/reference")
  end

  test "Phoenix never sets a Rails cookie" do
    conn = get(signed_in(), "/phoenix/reference")

    refute Enum.any?(
             get_resp_header(conn, "set-cookie"),
             &String.starts_with?(&1, ["_dawarich_session=", "remember_user_token="])
           )
  end

  test "an owned GET route answers HEAD without a body" do
    conn = head(signed_in(), "/phoenix/reference")

    assert conn.status == 200
    assert conn.resp_body == ""
  end

  test "inside the connected LiveView the app layout sees the self-hosted state Rails renders" do
    System.put_env("SELF_HOSTED", "true")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)
    {rails, _meta} = Dawarich.Test.LayoutFixtures.load("self_hosted_dark_en")
    {:ok, view, _html} = live(signed_in() |> connecting_as(@user["id"]), "/phoenix/reference")

    assert Dawarich.Test.ParityHTML.fragment(render(view), "footer") ==
             Dawarich.Test.ParityHTML.fragment(rails, "footer")
  end
end
