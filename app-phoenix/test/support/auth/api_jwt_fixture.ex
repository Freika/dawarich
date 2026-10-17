defmodule Dawarich.Test.ApiJwtFixture do
  @root Path.expand("../../fixtures/auth/api_auth", __DIR__)
  @external_resource Path.join(@root, "jwt_inputs.json")
  @inputs @external_resource |> File.read!() |> Jason.decode!()

  def secret(role), do: @inputs["synthetic_secret_marker"] <> "-" <> role
  def now, do: @inputs["now"] |> DateTime.from_iso8601() |> elem(1)
  def user_id, do: @inputs["user_id"]

  def vectors do
    @root
    |> Path.join("jwt_vectors.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("vectors")
    |> Enum.map(fn row ->
      case row["token"] do
        segments when is_list(segments) -> Map.put(row, "token", Enum.join(segments, "."))
        _ -> row
      end
    end)
  end
end
