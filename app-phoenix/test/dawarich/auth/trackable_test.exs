defmodule Dawarich.Auth.TrackableTest do
  use ExUnit.Case, async: true

  alias Dawarich.Auth.Trackable

  @now ~U[2026-10-01 12:00:00.123456Z]
  @old ~U[2026-09-30 12:00:00.654321Z]
  @ip "192.0.2.10"

  test "first authentication initializes both current and previous history" do
    user = %{sign_in_count: 0, current_sign_in_at: nil, current_sign_in_ip: nil}

    assert Trackable.changes(user, @now, @ip) == %{
             sign_in_count: 1,
             current_sign_in_at: @now,
             last_sign_in_at: @now,
             current_sign_in_ip: @ip,
             last_sign_in_ip: @ip
           }
  end

  test "later authentication retains the previous current event" do
    user = %{sign_in_count: 4, current_sign_in_at: @old, current_sign_in_ip: "192.0.2.20"}
    changes = Trackable.changes(user, @now, @ip)
    assert changes.sign_in_count == 5
    assert changes.last_sign_in_at == @old
    assert changes.current_sign_in_at == @now
    assert changes.last_sign_in_ip == "192.0.2.20"
    assert changes.current_sign_in_ip == @ip
  end

  test "missing legacy fields fall back independently" do
    user = %{sign_in_count: nil, current_sign_in_at: @old, current_sign_in_ip: nil}
    changes = Trackable.changes(user, @now, @ip)
    assert changes.sign_in_count == 1
    assert changes.last_sign_in_at == @old
    assert changes.last_sign_in_ip == @ip
  end

  test "matches actual pinned Devise output without Rails or database startup" do
    fixture =
      __DIR__
      |> Path.join("../../fixtures/auth/trackable.json")
      |> File.read!()
      |> Jason.decode!()

    assert fixture["devise_version"] == "5.0.4"

    for row <- fixture["cases"] do
      before = row["before"]

      user = %{
        sign_in_count: before["sign_in_count"],
        current_sign_in_at: datetime(before["current_sign_in_at"]),
        current_sign_in_ip: before["current_sign_in_ip"]
      }

      actual =
        user
        |> Trackable.changes(datetime(fixture["now"]), fixture["remote_ip"])
        |> Map.new(fn
          {key, %DateTime{} = value} -> {Atom.to_string(key), DateTime.to_iso8601(value)}
          {key, value} -> {Atom.to_string(key), value}
        end)

      assert actual == row["after"], row["name"]
    end
  end

  defp datetime(nil), do: nil
  defp datetime(value), do: value |> DateTime.from_iso8601() |> elem(1)
end
