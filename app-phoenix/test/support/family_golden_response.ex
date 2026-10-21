defmodule Dawarich.Test.FamilyGoldenResponse do
  import ExUnit.Assertions
  alias Dawarich.Test.ApiGolden

  @secret "family-golden-synthetic-jwt-key"

  def secret, do: @secret

  def check(kase, port, upstream) do
    options =
      if kase["name"] in ["rails_cloud_locations", "rails_cloud_create"] do
        [crypto: &checkout(&1, kase), crypto_etag: false]
      else
        []
      end

    ApiGolden.check(kase, port, upstream, options)
  end

  defp checkout(raw, kase) do
    url = Jason.decode!(raw)["upgrade_url"]
    assert URI.parse(url).path == "/auth/dawarich"
    token = URI.decode_query(URI.parse(url).query)["token"]
    [head, body, signature] = String.split(token, ".")
    assert Base.url_decode64!(head, padding: false) |> Jason.decode!() == %{"alg" => "HS256"}

    assert Plug.Crypto.secure_compare(
             Base.url_decode64!(signature, padding: false),
             :crypto.mac(:hmac, :sha256, @secret, head <> "." <> body)
           )

    claims = body |> Base.url_decode64!(padding: false) |> Jason.decode!()
    assert claims["purpose"] == "checkout"
    assert claims["exp"] == DateTime.to_unix(~U[2037-01-15 10:30:00Z]) + 1800
    id = if kase["name"] == "rails_cloud_locations", do: 880_001, else: 890_001
    assert claims["user_id"] == id

    assert claims["email"] ==
             if(id == 880_001,
               do: "family-owner@example.invalid",
               else: "writes-owner@example.invalid"
             )

    assert {:ok, _} = Ecto.UUID.cast(claims["jti"])
    String.replace(raw, token, "redacted")
  end
end
