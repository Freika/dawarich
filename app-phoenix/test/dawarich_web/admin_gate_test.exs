defmodule DawarichWeb.AdminGateTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.AdminGate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    original = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if original,
        do: System.put_env("SELF_HOSTED", original),
        else: System.delete_env("SELF_HOSTED")
    end)

    for {id, admin} <- [{10001, true}, {10002, false}],
        do:
          RailsUser.insert!(%{
            id: id,
            email: "a10-gate-#{id}@example.invalid",
            admin: admin,
            api_key: "a10-k-" <> to_string(id),
            settings: %{"timezone" => "Europe/Berlin"}
          })

    :ok
  end

  test "instance gate refuses guest nonadmin and Cloud before Phoenix filters" do
    assert false == AdminGate.instance?(conn(:get, "/admin/settings"), %{})
    assert false == AdminGate.instance?(signed(10002, "/admin/settings"), %{})
    assert true == AdminGate.instance?(signed(10001, "/admin/settings?section=photon"), %{})
    System.put_env("SELF_HOSTED", "false")
    assert false == AdminGate.instance?(signed(10001, "/admin/settings"), %{})
    System.put_env("SELF_HOSTED", "true")

    for query <- [
          "section[]=photon",
          "client=mobile",
          "aff=fixture",
          "via=fixture",
          "_method=post",
          "section=photon&section=points"
        ] do
      assert false == AdminGate.instance?(signed(10001, "/admin/settings?" <> query), %{})
    end

    for header <- ["turbo-frame", "x-dawarich-client", "x-http-method-override"] do
      assert false ==
               AdminGate.instance?(
                 put_req_header(signed(10001, "/admin/settings"), header, "synthetic"),
                 %{}
               )
    end

    duplicate = signed(10001, "/admin/settings")

    duplicate = %{
      duplicate
      | req_headers: [{"accept", "text/html"}, {"accept", "*/*"} | duplicate.req_headers]
    }

    assert false == AdminGate.instance?(duplicate, %{})

    assert false ==
             AdminGate.instance?(
               signed(10001, "/admin/settings", %{"dawarich_client" => "fixture"}),
               %{}
             )

    Repo.query!(
      "UPDATE users SET settings = '{\"timezone\": \"Mars/Unknown\"}' WHERE id = 10001",
      [],
      log: false
    )

    assert false == AdminGate.instance?(signed(10001, "/admin/settings"), %{})
  end

  test "users gate preserves Cloud-before-auth refusal and missing IDs" do
    assert true == AdminGate.users?(signed(10001, "/settings/users"), %{})
    assert true == AdminGate.users?(signed(10001, "/settings/users/10002"), %{"id" => "10002"})

    for id <- ~w(export 99999 0 -1 010002 1x 9999999999999999999999999) do
      assert false == AdminGate.users?(signed(10001, "/settings/users/" <> id), %{"id" => id})
    end

    assert false == AdminGate.users?(signed(10002, "/settings/users"), %{})
    assert false == AdminGate.users?(conn(:get, "/settings/users"), %{})
    assert false == AdminGate.users?(signed(10001, "/settings/users?search[]=a"), %{})
    assert false == AdminGate.users?(signed(10001, "/settings/users?page[]=2"), %{})
    Repo.query!("UPDATE users SET api_key = '' WHERE id = 10002", [], log: false)
    assert false == AdminGate.users?(signed(10001, "/settings/users/10002"), %{"id" => "10002"})

    assert true ==
             AdminGate.users?(signed(10001, "/settings/users/10002/edit"), %{"id" => "10002"})

    Repo.query!("UPDATE users SET deleted_at = now() WHERE id = 10002", [], log: false)
    assert false == AdminGate.users?(signed(10001, "/settings/users/10002"), %{"id" => "10002"})
    System.put_env("SELF_HOSTED", "false")
    assert false == AdminGate.users?(signed(10001, "/settings/users"), %{})
    assert false == AdminGate.users?(conn(:get, "/settings/users"), %{})
  end

  test "background gate allows a self-hosted nonadmin" do
    assert true == AdminGate.background?(signed(10002, "/settings/background_jobs"), %{})
    assert false == AdminGate.background?(conn(:get, "/settings/background_jobs"), %{})
    System.put_env("SELF_HOSTED", "false")
    assert false == AdminGate.background?(signed(10002, "/settings/background_jobs"), %{})
  end

  defp signed(id, url, extra \\ %{}) do
    cookie = RailsUser.cookie(RailsUser.session(id, extra))
    conn(:get, url) |> put_req_cookie("_dawarich_session", cookie)
  end
end
