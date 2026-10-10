defmodule DawarichWeb.NativeM7RouteLedgerTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.Router

  @inventory Path.expand("../../../docs/phoenix/native-m7-inventory.md", __DIR__)

  test "route ledger retains every compiled route and admission boundary" do
    rows =
      @inventory
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/^\| R[0-9]{3} \|/, &1))
      |> Enum.map(fn line ->
        [id, method, path, handler, pipelines, live, metadata, policy, owner, status] =
          line |> String.trim("|") |> String.split(" | ") |> Enum.map(&String.trim/1)

        assert policy != ""
        assert owner != ""
        assert status != ""
        assert id != ""
        Enum.map([method, path, handler, pipelines, live, metadata], &String.trim(&1, "`"))
      end)

    expected =
      for route <- Router.__routes__() do
        method = route.verb |> to_string() |> String.upcase()
        info = Phoenix.Router.route_info(Router, method, route.path, "www.example.com")

        live =
          case route.metadata[:phoenix_live_view] do
            {module, action, _options, %{name: session}} ->
              "#{inspect(module)}:#{action}@#{session}"

            nil ->
              "-"
          end

        [
          method,
          route.path,
          "#{inspect(route.plug)} #{inspect(route.plug_opts)}",
          Enum.join(info.pipe_through, ","),
          live,
          inspect(Map.take(route.metadata, [:rails_gate, :rails_key, :slice, :native_api, :retired]))
        ]
      end

    assert length(rows) > 300
    assert length(rows) == length(Enum.uniq(rows))
    assert Enum.sort(rows) == Enum.sort(expected)
  end
end
