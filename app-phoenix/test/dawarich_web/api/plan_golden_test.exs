defmodule DawarichWeb.Api.PlanGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_foundation/golden.json" |> File.read!() |> Jason.decode!()

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)

      if @kase["request"]["target"] in ~w(/api/v1/health /api/v1/ready) and
           @kase["expect"] == "rails" do
        routes = Application.get_env(:dawarich, :rails_routes, [])
        Application.put_env(:dawarich, :rails_routes, ["health", "ready"])
        on_exit(fn -> Application.put_env(:dawarich, :rails_routes, routes) end)
      end

      for row <- @kase["setup"],
          do:
            Repo.query!(
              "INSERT INTO users SELECT * FROM json_populate_record(NULL::users, $1::text::json)",
              [Jason.encode!(row)]
            )

      ApiGolden.check(@kase, port, upstream)
    end
  end
end
