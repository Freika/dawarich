defmodule DawarichWeb.NativeM7RouteLedgerTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.Router

  @inventory Path.expand("../../../docs/phoenix/native-m7-inventory.md", __DIR__)
  @web Path.expand("../../lib/dawarich_web", __DIR__)

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
          inspect(Map.take(route.metadata, [:native_api, :retired, :head, :native_page]))
        ]
      end

    assert length(rows) > 300
    assert length(rows) == length(Enum.uniq(rows))
    assert Enum.sort(rows) == Enum.sort(expected)
  end

  test "route ledger assigns every source macro and gate a retained contract" do
    ledger = File.read!(@inventory)

    macros =
      for file <- Path.wildcard(Path.join(@web, "*routes.ex")),
          [_, name] <- Regex.scan(~r/defmacro (\w+)/, File.read!(file)) do
        [_, module] = Regex.run(~r/defmodule ([\w.]+)/, File.read!(file))
        "#{module}.#{name}"
      end

    assert length(macros) > 25

    for macro <- macros do
      assert ledger =~ "| M:#{macro} |"
    end

    gates =
      for %{metadata: %{rails_gate: {module, function}}} <- Router.__routes__(),
          uniq: true,
          do: "#{inspect(module)}.#{function}"

    current =
      Regex.scan(~r/^\| CG:([^ |]+) \|/m, ledger)
      |> Enum.map(fn [_, gate] -> gate end)

    assert gates == []
    assert current == []

    for gate <- gates do
      assert ledger =~ "| G:#{gate} |"
    end
  end

  test "external client ledger explicitly decides every implemented Cable channel" do
    source = File.read!(Path.join(@web, "../dawarich/cable/channels.ex"))
    [_, names] = Regex.run(~r/@names ~w\(([^)]+)\)/, source)

    rows =
      @inventory
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| WIRE:"))
      |> Enum.map(fn line ->
        [id, stream, consumer, contract, disposition, owner] =
          line |> String.trim("|") |> String.split(" | ") |> Enum.map(&String.trim/1)

        assert Enum.all?([stream, consumer, contract, disposition, owner], &(&1 != ""))

        assert String.starts_with?(disposition, "retain") or
                 String.starts_with?(disposition, "unknown")

        String.replace_prefix(id, "WIRE:", "")
      end)

    assert Enum.sort(rows) == Enum.sort(String.split(names))
  end
end
