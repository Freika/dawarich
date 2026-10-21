defmodule Dawarich.TripStreamTest do
  use ExUnit.Case, async: true

  alias Dawarich.{RailsMessages, TripStream}

  test "a trip signs its GlobalID using the existing Turbo stream signer" do
    secret = "a8-secret"
    global_id = Base.url_encode64("gid://dawarich/Trip/5", padding: false)
    signed = TripStream.stream_name(5, secret)

    assert signed == RailsMessages.stream_name([global_id], secret)
    [data, digest] = String.split(signed, "--")
    assert Base.decode64!(data) == Jason.encode!(global_id)
    assert digest =~ ~r/\A[0-9a-f]{64}\z/
  end
end
