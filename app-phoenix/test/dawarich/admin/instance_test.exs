defmodule Dawarich.Admin.InstanceTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.{Instance, InstancePage}
  alias Dawarich.Test.RailsUser

  defmodule AtlasFailureRepo do
    defdelegate transaction(fun), to: Dawarich.Repo

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "INSERT INTO instance_settings") and hd(params) == "atlas_url",
        do: raise("synthetic atlas persistence failure"),
        else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("DELETE FROM instance_settings", [], log: false)

    RailsUser.insert!(%{
      id: 15601,
      email: "instance-context-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    test_pid = self()

    %{
      scope: Scope.for_user(Accounts.get(15601), "en"),
      opts: [
        env: %{"SELF_HOSTED" => "true"},
        command: fn command -> send(test_pid, {:published, command}) && {:ok, 1} end
      ]
    }
  end

  defp stored,
    do: Repo.query!("SELECT key, value FROM instance_settings ORDER BY key", [], log: false).rows

  test "a section save stores its fields and reports saved", c do
    params = %{"section" => "points", "instance_settings" => %{"store_geodata" => "false"}}

    assert Instance.save(c.scope, params, c.opts) == {:ok, :saved}
    assert stored() == [["store_geodata", false]]
    assert_received {:published, ["PUBLISH", "dawarich:instance_settings", _]}
  end

  test "the experimental save follows the rendered order, so a failing atlas_url leaves map matching off",
       c do
    assert InstancePage.field_order("experimental") |> hd() == "atlas_url"

    params = %{
      "section" => "experimental",
      "instance_settings" => %{
        "map_matching_enabled" => "true",
        "map_matching_shadow_mode" => "false",
        "atlas_url" => "http://atlas.example.invalid"
      }
    }

    assert Instance.save(c.scope, params, Keyword.put(c.opts, :repo, AtlasFailureRepo)) ==
             {:error, :unavailable}

    assert stored() == []
  end

  test "fields pinned by the environment are refused one by one", c do
    opts = Keyword.put(c.opts, :env, %{"SELF_HOSTED" => "true", "STORE_GEODATA" => "true"})

    params = %{
      "section" => "rate_limit",
      "instance_settings" => %{"reverse_geocoding_rps" => "3"}
    }

    assert Instance.save(c.scope, params, opts) == {:ok, :saved}

    pinned = %{"section" => "points", "instance_settings" => %{"store_geodata" => "false"}}
    assert Instance.save(c.scope, pinned, opts) == {:ok, {:pinned, ["STORE_GEODATA"]}}
    assert stored() == [["reverse_geocoding_rps", 3.0]]
  end

  test "fields outside the submitted section are ignored", c do
    params = %{
      "section" => "points",
      "instance_settings" => %{"store_geodata" => "false", "reverse_geocoding_rps" => "9"}
    }

    assert Instance.save(c.scope, params, c.opts) == {:ok, :saved}
    assert stored() == [["store_geodata", false]]
  end

  test "a demoted, stale or OIDC actor writes and publishes nothing", c do
    params = %{"section" => "points", "instance_settings" => %{"store_geodata" => "false"}}

    oidc =
      Keyword.put(c.opts, :env, %{
        "SELF_HOSTED" => "true",
        "OIDC_CLIENT_ID" => "synthetic",
        "OIDC_CLIENT_SECRET" => "x"
      })

    assert Instance.save(c.scope, params, oidc) == {:error, :oidc}
    assert Instance.test_geocoding(c.scope, oidc) == {:error, :oidc}

    Repo.query!("UPDATE users SET admin = false WHERE id = 15601")
    assert Instance.save(c.scope, params, c.opts) == {:error, :unauthorized}
    assert Instance.test_map_matching(c.scope, c.opts) == {:error, :unauthorized}

    Repo.query!("UPDATE users SET admin = true, deleted_at = now() WHERE id = 15601")
    assert Instance.save(c.scope, params, c.opts) == {:error, :stale_session}

    assert stored() == []
    refute_received {:published, _}
  end

  test "an unknown section is refused", c do
    assert Instance.save(c.scope, %{"section" => "nope"}, c.opts) == {:error, :invalid_section}
  end

  test "the Atlas test without a configured URL returns the not-configured alert", c do
    assert Instance.test_map_matching(c.scope, c.opts) ==
             {:alert, "admin.settings.test_map_matching.not_configured", %{}}
  end
end
