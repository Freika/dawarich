defmodule Dawarich.Front.CommandTest do
  use ExUnit.Case, async: true

  alias Dawarich.Front.Command

  @prod %{"RAILS_ENV" => "production"}
  @any4 {0, 0, 0, 0}
  @any6 {0, 0, 0, 0, 0, 0, 0, 0}

  defp parse(argv, env \\ @prod, ipv6? \\ false), do: Command.parse(argv, env, 41_000, ipv6?)

  test "the compose command: Phoenix takes [::]:3000 and Puma moves to loopback" do
    assert parse(~w(bundle exec bin/rails server -p 3000 -b ::)) ==
             {:ok, {@any6, 3000}, ~w(bundle exec bin/rails server -b 127.0.0.1 -p 41000)}
  end

  test "every spelling of the Rails port and binding options is understood" do
    for argv <- [
          ~w(bundle exec bin/rails server --port 3000 --binding 0.0.0.0),
          ~w(bundle exec bin/rails server --port=3000 --binding=0.0.0.0),
          ~w(bundle exec bin/rails s -p3000 -b0.0.0.0),
          ~w(bundle exec rails server -p 3000 -b 0.0.0.0)
        ] do
      assert {:ok, {@any4, 3000}, puma} = parse(argv)
      assert Enum.take(puma, -4) == ~w(-b 127.0.0.1 -p 41000)
      refute Enum.any?(puma, &String.contains?(&1, "3000"))
    end
  end

  test "Rails' own defaults apply when the command names no port or binding" do
    argv = ~w(bundle exec bin/rails server)

    assert {:ok, {@any4, 3000}, _} = parse(argv)
    assert {:ok, {@any4, 4100}, _} = parse(argv, Map.put(@prod, "PORT", "4100"))
    assert {:ok, {{127, 0, 0, 1}, 3000}, _} = parse(argv, %{})
    assert {:ok, {{127, 0, 0, 1}, 3000}, _} = parse(argv, %{"RACK_ENV" => "development"})
    assert {:ok, {{10, 0, 0, 5}, 3000}, _} = parse(argv, Map.put(@prod, "BINDING", "10.0.0.5"))
  end

  test "the last of repeated Rails options wins, as in Rails' option parser" do
    assert {:ok, {@any4, 3002}, _} = parse(~w(bundle exec bin/rails server -p 3001 -p 3002))
  end

  test "other options keep their order in front of the loopback binding" do
    assert {:ok, _, puma} =
             parse(~w(bundle exec bin/rails server -e production -p 3000 -P tmp/pids/x.pid))

    assert puma ==
             ~w(bundle exec bin/rails server -e production -P tmp/pids/x.pid -b 127.0.0.1 -p 41000)
  end

  test "the Cloud Procfile command: Phoenix takes 5000 on Puma's default host" do
    argv = ~w(bundle exec puma -C config/puma.rb -p 5000)

    assert parse(argv, @prod, false) ==
             {:ok, {@any4, 5000}, ~w(bundle exec puma -C config/puma.rb -b tcp://127.0.0.1:41000)}

    assert {:ok, {@any6, 5000}, _} = parse(argv, @prod, true)
  end

  test "a single Puma tcp bind names Phoenix's address" do
    assert {:ok, {@any6, 3000}, puma} = parse(~w(bundle exec puma --bind tcp://[::]:3000))
    assert puma == ~w(bundle exec puma -b tcp://127.0.0.1:41000)
    assert {:ok, {@any4, 3000}, _} = parse(~w(bundle exec puma -b tcp://0.0.0.0:3000))
  end

  test "Puma without a port or bind listens where config/puma.rb says: PORT or 3000" do
    assert {:ok, {@any4, 3000}, _} = parse(~w(bundle exec puma -C config/puma.rb))
    assert {:ok, {@any4, 3000}, _} = parse(~w(bundle exec puma))
    assert {:ok, {@any4, 3900}, _} = parse(~w(bundle exec puma), Map.put(@prod, "PORT", "3900"))
  end

  test "commands Phoenix cannot front are left alone, with a reason" do
    for argv <- [
          ["sh", "-c", "exit 0"],
          ~w(bundle exec bin/dev),
          ~w(bundle exec puma -C config/other_puma.rb),
          ~w(bundle exec puma -b ssl://0.0.0.0:3000),
          ~w(bundle exec puma -b unix:///tmp/puma.sock),
          ~w(bundle exec puma -b tcp://0.0.0.0:3000 -b tcp://0.0.0.0:3001),
          ~w(bundle exec puma -p 3000 -p 3001),
          ~w(bundle exec puma -p 3000 -b tcp://0.0.0.0:3001),
          ~w(bundle exec bin/rails server -b example.com),
          ~w(bundle exec bin/rails server -p http)
        ] do
      assert {:direct, reason} = parse(argv)
      assert <<_, _::binary>> = reason
    end
  end
end
