defmodule Dawarich.Auth.TwoFactor.TotpTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.TwoFactor.Totp

  @oracle "../../../fixtures/auth/two_factor/otp.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()

  test "web TOTP matches Rails drift whitespace and consumed timesteps" do
    assert Code.ensure_loaded?(Totp)
    entropy = Base.decode16!(@oracle["entropy_hex"], case: :mixed)
    secret = Totp.generate_secret(entropy)

    for row <- @oracle["vectors"] do
      expected = if row["valid"], do: {:ok, row["result_timestep"]}, else: :invalid
      assert Totp.verify(secret, row["code"], row["at"], row["consumed"]) == expected, row["name"]
    end

    assert Totp.verify(secret, nil, 1_791_115_200) == :invalid
    assert Totp.verify(nil, "123456", 1_791_115_200) == :invalid
    assert Totp.decode("gEzD=GNBVGY3TQOJQGEZDGNBVGY3TQOJQ===") == entropy
    assert Totp.decode("A") == ""
    assert_raise ArgumentError, fn -> Totp.decode("not-valid-base32!") end
  end

  test "API direct TOTP accepts only the one-second Rails windows" do
    secret = Totp.generate_secret(Base.decode16!(@oracle["entropy_hex"], case: :mixed))

    vectors = [
      {1_791_115_200, "446537", {:ok, 59_703_839}},
      {1_791_115_201, "446537", :invalid},
      {1_791_115_228, "478842", :invalid},
      {1_791_115_229, "478842", {:ok, 59_703_841}},
      {1_791_115_230, "923731", {:ok, 59_703_840}},
      {1_791_115_231, "923731", :invalid},
      {1_791_115_200, "923731", {:ok, 59_703_840}},
      {1_791_115_200, "923731", {:ok, 59_703_840}},
      {1_791_115_200, " 923731 ", :invalid},
      {1_791_115_200, "923\n731", :invalid},
      {1_791_115_200, "0923731", :invalid},
      {1_791_115_590, "046907", {:ok, 59_703_853}},
      {1_791_115_590, "46907", :invalid}
    ]

    for {now, code, expected} <- vectors do
      assert Totp.api_verify(secret, code, now) == expected
    end

    assert Totp.api_verify(nil, "923731", 1_791_115_200) == :invalid
    assert Totp.api_verify(secret, nil, 1_791_115_200) == :invalid
  end

  test "provisioning URI and secret shape match Devise and ROTP" do
    assert Code.ensure_loaded?(Totp)
    entropy = Base.decode16!(@oracle["entropy_hex"], case: :mixed)
    secret = Totp.generate_secret(entropy)
    expected = @oracle["labels"] |> hd() |> Map.fetch!("uri") |> URI.parse()
    assert secret == URI.decode_query(expected.query)["secret"]
    generated = Totp.generate_secret()
    assert byte_size(generated) == 32
    assert generated =~ ~r/\A[A-Z2-7]{32}\z/
    assert byte_size(Totp.decode(generated)) == 20

    for row <- @oracle["labels"] do
      assert Totp.provisioning_uri(secret, row["label"]) == row["uri"]
    end

    assert Totp.provisioning_uri(secret, " a:b+ü ", " Daw:arich ") ==
             "otpauth://totp/Daw_arich:%20a_b%2B%C3%BC?secret=#{secret}&issuer=Daw_arich"
  end
end
