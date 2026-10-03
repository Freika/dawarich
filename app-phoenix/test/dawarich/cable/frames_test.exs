defmodule Dawarich.Cable.FramesTest do
  use ExUnit.Case, async: true

  alias Dawarich.Cable.Frames
  alias Dawarich.Test.A12a

  defp frames(name), do: for(%{"expect" => f} <- A12a.case!(name)["steps"], do: f)

  test "control frames equal Rails' bytes" do
    assert hd(frames("user")) == Frames.welcome()
    assert frames("anonymous") == [Frames.disconnect("unauthorized", false)]
    [_welcome, confirm] = frames("points_user")
    assert confirm == Frames.confirm(~s({"channel":"PointsChannel"}))
    [_welcome, reject] = frames("points_share_only")
    assert reject == Frames.reject(~s({"channel":"PointsChannel"}))
    sample = A12a.corpus()["pings"]["sample"]
    assert {:ok, %{"type" => "ping", "message" => seconds}} = Jason.decode(sample)
    assert Frames.ping(seconds) == sample
  end

  test "a relayed message splices the raw payload and escapes the identifier as Rails does" do
    for %{"steps" => steps} = c <- A12a.cases("messages") do
      payloads = for %{"publish" => p} <- steps, do: p["payload"]
      relayed = for %{"expect" => f} <- steps, String.contains?(f, ~s("message":)), do: f
      assert relayed == Enum.map(payloads, &Frames.message(A12a.identifier(c), &1)), c["name"]
    end

    [_welcome, confirm] = frames("identifier_ampersand")
    identifier = ~s({"channel":"PointsChannel","x":"&"})
    assert confirm == Frames.confirm(identifier)
    rails = String.replace(confirm, ~s("type":"confirm_subscription"}), ~s("message":[1]}))
    assert Frames.message(identifier, "[1]") == rails
  end

  test "payload/1 encodes producer terms as ActiveSupport JSON" do
    for %{"input" => input, "payload" => payload} <- A12a.corpus()["producers"] do
      assert Frames.payload(A12a.term(input)) == payload
    end
  end
end
