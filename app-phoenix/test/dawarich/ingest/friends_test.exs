defmodule Dawarich.Ingest.FriendsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Ingest.{Friends, Unsupported}

  defp sharing(expires),
    do: %{"family" => %{"location_sharing" => %{"enabled" => true, "expires_at" => expires}}}

  defp member!(family, settings, attrs \\ %{}) do
    id = user!(Map.put(attrs, :settings, settings))
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("family_memberships", [
      %{family_id: family, user_id: id, role: 1, created_at: stamp, updated_at: stamp}
    ])

    id
  end

  defp point!(user, ts, extra) do
    stamp = NaiveDateTime.utc_now()

    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, battery, battery_status, anomaly, created_at, updated_at) VALUES ($1, $2, 'SRID=4326;POINT(13.4 52.5)', $3, $4, $5, $6, $6)",
      [user, ts, extra[:battery], extra[:bs], extra[:anomaly], stamp]
    )
  end

  test "cards and latest locations of sharing members, as FriendsFormatter builds them" do
    me = user!()
    stamp = NaiveDateTime.utc_now()

    {1, [%{id: family}]} =
      Repo.insert_all(
        "families",
        [%{name: "f", creator_id: me, created_at: stamp, updated_at: stamp}],
        returning: [:id]
      )

    Repo.insert_all("family_memberships", [
      %{family_id: family, user_id: me, role: 0, created_at: stamp, updated_at: stamp}
    ])

    a = member!(family, sharing("2099-01-01T00:00:00+00:00"))
    b = member!(family, sharing(nil))
    member!(family, %{"family" => %{"location_sharing" => %{"enabled" => false}}})
    expired = member!(family, sharing("2001-01-01T00:00:00Z"))
    gone = member!(family, sharing(nil), %{deleted_at: stamp})
    for u <- [me, expired, gone], do: point!(u, 5, %{})
    point!(a, 10, %{battery: 55, bs: 5})
    point!(a, 20, %{anomaly: true})

    tid = Integer.to_string(a, 36)

    assert [
             {:object, [{"_type", "card"}, {"tid", ^tid}, {"name", _}]},
             {:object,
              [
                {"_type", "location"},
                {"tid", ^tid},
                {"lat", 52.5},
                {"lon", 13.4},
                {"tst", 10},
                {"batt", 55},
                {"bs", 1}
              ]}
           ] = Friends.for_user(me)

    tid_b = Integer.to_string(b, 36)
    refute Enum.any?(Friends.for_user(me), &match?({:object, [_, {"tid", ^tid_b} | _]}, &1))
  end

  test "no family, no friends; an expiry that is not ISO 8601 with an offset goes to Rails" do
    assert Friends.for_user(user!()) == []

    me = user!()
    stamp = NaiveDateTime.utc_now()

    {1, [%{id: family}]} =
      Repo.insert_all(
        "families",
        [%{name: "f", creator_id: me, created_at: stamp, updated_at: stamp}],
        returning: [:id]
      )

    Repo.insert_all("family_memberships", [
      %{family_id: family, user_id: me, role: 0, created_at: stamp, updated_at: stamp}
    ])

    member!(family, sharing("tomorrow"))
    assert_raise Unsupported, fn -> Friends.for_user(me) end
  end
end
