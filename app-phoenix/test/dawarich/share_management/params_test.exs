defmodule Dawarich.ShareManagement.ParamsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Repo
  alias Dawarich.ShareManagement.Params

  @user %{id: 98101, settings: %{"timezone" => "Europe/Berlin"}}

  setup do
    :ok
  end

  test "expiry uses local midnight and malformed date becomes nil" do
    assert Params.expiry_from("malformed", @user.settings) == nil
    assert Params.expiry_from("", @user.settings) == nil
    assert Params.expiry_from(nil, @user.settings) == nil

    for zone <- ~w(UTC America/Havana Asia/Tokyo Europe/Berlin) do
      fixture =
        "test/fixtures/share_management/live_expiry_#{String.replace(zone, "/", "_")}_en.json"
        |> File.read!()
        |> Jason.decode!()

      created =
        Enum.find(
          fixture["after"],
          &(&1["id"] not in Enum.map(fixture["before"], fn row -> row["id"] end))
        )

      expected = NaiveDateTime.from_iso8601!(created["expires_at"])
      assert Params.expiry_from("2026-11-01", %{"timezone" => zone}) == expected
    end

    assert Params.expiry_from("2026-10-25", @user.settings) == ~N[2026-10-24 22:00:00]
    assert Params.expiry_from("2026-10-26", @user.settings) == ~N[2026-10-25 23:00:00]
  end

  @now ~U[2026-10-03 10:00:00Z]

  test "settings preserve Rails boolean casts defaults and whitelist" do
    fixture =
      "test/fixtures/share_management/live_settings_en.json" |> File.read!() |> Jason.decode!()

    assert {:ok, attrs} = Params.create(@user, "live", nil, fixture["params"], "en")
    created = List.last(fixture["after"])
    assert attrs.settings == created["settings"]

    assert {:ok, trip} =
             Params.create(@user, "trip", %{id: 99101, name: "Leipzig Weekend"}, %{}, "en")

    assert trip.settings == %{"show_photos" => false, "show_stats" => false}
    assert trip.name == "Trip: Leipzig Weekend"
    assert {:ok, live} = Params.create(@user, "live", nil, %{}, "en")
    assert live.settings == %{"show_photos" => false, "show_route" => false}

    for value <- [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"] do
      assert {:ok, %{settings: %{"show_route" => false}}} =
               Params.create(
                 @user,
                 "live",
                 nil,
                 %{"shared_link" => %{"settings" => %{"show_route" => value}}},
                 "en"
               )
    end
  end

  test "name phrase and expiry validation match Rails without new constraints" do
    assert {:ok, attrs} =
             Params.create(
               @user,
               "live",
               nil,
               %{"shared_link" => %{"name" => " ", "magic_phrase" => " "}},
               "en"
             )

    assert attrs.name == "Live location"
    assert attrs.magic_phrase == nil
    assert Params.validate(attrs, @now, "en") == []

    assert Params.validate(%{attrs | name: String.duplicate("a", 256)}, @now, "en") ==
             [{:name, "Name is too long (maximum is 255 characters)"}]

    assert Params.validate(%{attrs | name: String.duplicate("a", 256)}, @now, "de") ==
             [{:name, "Name ist zu lang (mehr als 255 Zeichen)"}]

    assert Params.validate(%{attrs | magic_phrase: String.duplicate("a", 256)}, @now, "en") ==
             [{:magic_phrase, "Magic phrase is too long (maximum is 255 characters)"}]

    assert Params.validate(%{attrs | name: String.duplicate("é", 128)}, @now, "en") != []

    assert Params.validate(%{attrs | expires_at: DateTime.to_naive(@now)}, @now, "en") ==
             [{:expires_at, "Expires at must be in the future"}]

    assert Params.validate(%{attrs | expires_at: ~N[2026-10-04 00:00:00]}, @now, "en") == []
    expired = %{attrs | expires_at: ~N[2026-10-02 00:00:00]}
    assert Params.validate(expired, @now, "en", original: expired) == []
    assert Params.validate(%{attrs | name: ""}, @now, "en") == [{:name, "Name can't be blank"}]
  end

  test "unknown shapes replay without mutating rows" do
    before = Repo.query!("SELECT count(*) FROM shared_links").rows

    for params <- [
          %{"shared_link" => %{"name" => %{"nested" => "name"}}},
          %{"shared_link" => []},
          %{"shared_link" => %{"magic_phrase" => ["phrase"]}},
          %{"shared_link" => %{"expires_at" => %{}}},
          %{"shared_link" => %{"expires_at" => "20261101"}},
          %{"shared_link" => %{"expires_at" => "2026-305"}},
          %{"shared_link" => %{"expires_at" => "2026-W44-7"}},
          %{"shared_link" => %{"settings" => "1"}},
          %{"shared_link" => %{"settings" => %{"show_route" => []}}},
          %{"locale" => "de"},
          %{"format" => "json"},
          %{"_method" => "PATCH"}
        ] do
      assert Params.create(@user, "live", nil, params, "en") == :rails
    end

    assert Params.create(@user, "timeline", nil, %{}, "en") == :rails
    assert Params.create(%{@user | settings: []}, "live", nil, %{}, "en") == :rails

    assert Params.create(%{@user | settings: %{"timezone" => []}}, "live", nil, %{}, "en") ==
             :rails

    assert Repo.query!("SELECT count(*) FROM shared_links").rows == before
  end
end
