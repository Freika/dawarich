defmodule Dawarich.Auth.RegistrationAttributionTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.RegistrationAttribution

  test "R1 decomposed referral matches Rails truncate at 255 codepoints" do
    input = String.duplicate("e\u0301", 255)
    stored = RegistrationAttribution.store(%{}, %{"aff" => input, "via" => "losing-key"})
    referral = stored["partnero_referral"]
    assert length(String.codepoints(referral)) == 255
    assert referral == String.duplicate("e\u0301", 127) <> "e"
    assert String.valid?(referral)
  end
end
