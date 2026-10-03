defmodule Dawarich.Families.SharingTest do
  use ExUnit.Case, async: true

  alias Dawarich.Families.Sharing

  @now ~U[2026-10-01 12:00:00.000000Z]

  defp settings(expires_at),
    do: %{"family" => %{"location_sharing" => %{"enabled" => true, "expires_at" => expires_at}}}

  test "an expiry equal to now has expired, one microsecond later has not" do
    refute Sharing.enabled?(settings("2026-10-01T14:00:00+02:00"), @now)
    assert Sharing.enabled?(settings("2026-10-01T12:00:00.000001Z"), @now)
  end

  test "settings Rails cannot dig through raise instead of answering" do
    for bad <- [nil, [], "x", %{"family" => "x"}, %{"family" => []}, %{"family" => 1}] do
      assert_raise ArgumentError, fn -> Sharing.enabled?(bad, @now) end
    end

    for expires_at <- [
          true,
          0,
          ["x"],
          "2099-01-01",
          "2099-01-01 00:00:00Z",
          "2099-02-30T00:00:00Z"
        ] do
      assert_raise ArgumentError, fn -> Sharing.enabled?(settings(expires_at), @now) end
    end
  end
end
