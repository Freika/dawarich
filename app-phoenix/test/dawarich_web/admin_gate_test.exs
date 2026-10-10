defmodule DawarichWeb.AdminGateTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.AdminGate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.State.put_registration_enabled(Repo, false)
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
