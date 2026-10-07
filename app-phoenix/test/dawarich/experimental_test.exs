defmodule Dawarich.ExperimentalTest do
  use Dawarich.DataCase, async: false

  alias Dawarich.Admin.{InstancePage, InstanceWrites}
  alias Dawarich.{Accounts, Experimental, I18n}

  setup do
    on_exit(fn -> :persistent_term.put({Experimental, Repo, :map_matching}, false) end)
  end

  test "env pin overrides the stored value and reports pinned" do
    assert Code.ensure_loaded?(Experimental)
    setting!("map_matching_enabled", true)
    setting!("map_matching_shadow_mode", false)
    setting!("atlas_url", "http://stored.example.invalid")

    env = %{
      "MAP_MATCHING_ENABLED" => "false",
      "MAP_MATCHING_SHADOW_MODE" => "true",
      "ATLAS_URL" => "http://pinned.example.invalid"
    }

    assert Experimental.value(:map_matching_enabled, Repo, %{}) == true
    assert Experimental.value(:map_matching_enabled, Repo, env) == false
    assert Experimental.value(:map_matching_shadow_mode, Repo, env) == true
    assert Experimental.value(:atlas_url, Repo, env) == "http://pinned.example.invalid"
    assert Experimental.pinned?(:map_matching_enabled, env)
    refute Experimental.pinned?(:map_matching_enabled, %{"MAP_MATCHING_ENABLED" => " "})
    refute Experimental.enabled?(:map_matching, Repo, env)
    assert Experimental.enabled?(:map_matching, Repo, %{})

    assert [
             %{
               key: :map_matching,
               toggles: [:map_matching_enabled, :map_matching_shadow_mode],
               config: [:atlas_url],
               prerequisites: %{map_matching_enabled: [:atlas_url]},
               env: %{
                 map_matching_enabled: "MAP_MATCHING_ENABLED",
                 map_matching_shadow_mode: "MAP_MATCHING_SHADOW_MODE",
                 atlas_url: "ATLAS_URL"
               },
               label: label,
               description: description
             }
           ] = Experimental.entries()

    assert {:ok, page} = InstancePage.load(Repo, env)
    assert InstancePage.section(page, "experimental") == "experimental"

    assert InstancePage.section_keys("experimental") ==
             ~w(map_matching_enabled map_matching_shadow_mode atlas_url)

    assert page.fields["map_matching_enabled"].disabled
    assert page.fields["map_matching_enabled"].env_var == "MAP_MATCHING_ENABLED"
    assert InstancePage.section_status(page, "experimental") == :pinned

    actor = Accounts.get(user!(%{admin: true}))

    context = %{
      self_hosted: true,
      oidc: false,
      locale: "en",
      env: env,
      command: fn _ -> {:ok, 0} end
    }

    params = %{
      "instance_settings" => %{
        "map_matching_enabled" => "true",
        "atlas_url" => "http://other.example.invalid"
      }
    }

    assert {:ok, refused} = InstanceWrites.call(actor, params, context)
    assert Enum.sort(refused) == ~w(ATLAS_URL MAP_MATCHING_ENABLED)
    assert Experimental.value(:atlas_url, Repo, %{}) == "http://stored.example.invalid"
    assert {:ok, []} = InstanceWrites.call(actor, params, %{context | env: %{}})
    assert Experimental.value(:atlas_url, Repo, %{}) == "http://other.example.invalid"

    for locale <- ~w(en de fr es zh ca pl),
        key <- [
          label,
          description,
          "admin.settings.show.experimental.title",
          "admin.settings.show.fields.map_matching_shadow_mode",
          "admin.settings.show.fields.map_matching_shadow_mode_hint",
          "admin.settings.show.fields.atlas_url",
          "admin.settings.show.fields.atlas_url_hint",
          "admin.settings.show.fields.map_matching_enabled",
          "admin.settings.show.fields.map_matching_enabled_hint",
          "admin.settings.show.pinned_hint",
          "admin.settings.update.atlas_url_invalid",
          "admin.settings.update.atlas_url_required"
        ] do
      assert {:ok, text} =
               I18n.t(locale, key, %{"variable" => "MAP_MATCHING_ENABLED"}, fallback: false)

      assert is_binary(text) and text != ""
    end
  end

  test "map_matching_visible? is false in shadow mode" do
    assert Code.ensure_loaded?(Experimental)
    refute Experimental.map_matching?(Repo, %{})
    refute Experimental.map_matching_visible?(Repo, %{})
    setting!("map_matching_enabled", true)
    refute Experimental.map_matching?(Repo, %{})
    setting!("atlas_url", "http://atlas.example.invalid")
    assert Experimental.map_matching?(Repo, %{})
    assert Experimental.map_matching_visible?(Repo, %{})
    setting!("map_matching_shadow_mode", true)
    assert Experimental.map_matching?(Repo, %{})
    refute Experimental.map_matching_visible?(Repo, %{})
  end

  defp setting!(key, value) do
    rows(
      "INSERT INTO instance_settings(key,value,created_at,updated_at) VALUES($1,$2,now(),now()) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      [key, value]
    )
  end
end
