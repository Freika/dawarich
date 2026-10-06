defmodule Dawarich.Front.NativeCommandTest do
  use ExUnit.Case, async: true

  alias Dawarich.Front.Command

  @prod %{"RAILS_ENV" => "production"}
  @any4 {0, 0, 0, 0}
  @any6 {0, 0, 0, 0, 0, 0, 0, 0}

  test "Rails split listener flags refuse option tokens even before valid repeats" do
    private = "--synthetic-private-flag"

    for args <- [
          ~w(-p --unknown -p 3000),
          ~w(-b --daemon -b 127.0.0.1),
          ~w(--port --binding :: --port 3000),
          ~w(--binding -p 3000 --binding ::),
          ["-p", private, "-p", "3000"],
          ["-b", private, "-b", "::"]
        ] do
      assert {:error, reason} = Command.native(["rails", "server" | args], @prod)
      assert reason =~ "Rails server"
      assert reason =~ "dawarich start"
      refute reason =~ private
      assert {:error, ^reason} = Dawarich.Front.native_plan(["rails", "server" | args], @prod)
    end
  end

  test "Rails listener repeats validate every supplied value before choosing the last" do
    private = "synthetic-private-listener"

    for prefix <- [[], ~w(bundle exec)],
        rails <- ~w(rails bin/rails),
        server <- ~w(server s),
        args <- [
          ~w(--port=bad --port=3000),
          ~w(-p==3000 -p 3001),
          ~w(--binding=bad --binding=::),
          ~w(--port= --port=3000),
          ~w(-p 0 -p 3000),
          ~w(-p 65536 -p 3000),
          ["-b", "", "-b", "::"],
          ~w(-b 127.0.0.999 -b 127.0.0.1),
          ~w(-b [:: -b ::),
          ~w(-b ::] -b ::),
          ["-p", private, "--port=3000"],
          ["--binding=" <> private, "-b::"]
        ] do
      argv = prefix ++ [rails, server] ++ args
      assert {:error, reason} = Command.native(argv, @prod)
      assert reason =~ "Rails #{server}"
      assert reason =~ "dawarich start"
      refute reason =~ private
      assert {:error, ^reason} = Dawarich.Front.native_plan(argv, @prod)
    end

    env = Map.merge(@prod, %{"PORT" => private, "BINDING" => private})

    for prefix <- [[], ~w(bundle exec)], rails <- ~w(rails bin/rails), server <- ~w(server s) do
      assert Command.native(
               prefix ++ [rails, server] ++ ~w(-p 3001 --port=3002 -b127.0.0.1 --binding=[::]),
               env
             ) == {:web, {@any6, 3002}}
    end
  end

  test "unknown legacy commands and malformed listener arguments refuse with a native remedy" do
    private = "synthetic-private-argv"

    for argv <- [
          [],
          nil,
          [private],
          ["rails", "runner", private],
          ["rails", "console", private],
          ["rake", private],
          ["bundle", "exec", "rake", private],
          ~w(bundle exec),
          ~w(bundle exec bundle exec rails server),
          ~w(rails server -p),
          ~w(rails server --binding),
          ["rails", "server", "-p", private],
          ~w(rails server -p 0),
          ~w(rails server -p 65536),
          ~w(rails server -p -1),
          ~w(rails server -p==3000),
          ~w(rails server --port=),
          ["rails", "server", "-b", private],
          ~w(rails server -b 127.0.0.999),
          ~w(rails server -b [::),
          ~w(rails server -b ::]),
          ~w(rails server -e production),
          ["rails", "server", private],
          ~w(puma -p),
          ~w(puma -b tcp://127.0.0.1:0),
          ~w(puma -b tcp://127.0.0.1:65536),
          ~w(puma -b tcp://127.0.0.1:bad),
          ~w(puma -b tcp://user:password@127.0.0.1:5000),
          ["puma", "-C", private],
          ["puma", private],
          ["sidekiq", "-C", private],
          ~w(sidekiq -q default),
          ~w(sidekiq -c 5),
          ~w(sidekiq -C),
          ["sidekiq", private],
          ~w(rails db:migrate extra),
          ~w(rails db:seed extra),
          ~w(dawarich start extra),
          ~w(dawarich seeds extra),
          ~w(dawarich migrate extra),
          ["dawarich", "eval", private, "extra"]
        ] do
      assert {:error, reason} = Command.native(argv, @prod)
      assert reason =~ "command"
      assert reason =~ "dawarich"
      refute reason =~ private
      refute reason =~ "password"
    end

    for {argv, label} <- [
          {["rails", "runner", private], "Rails runner"},
          {["rails", "console", private], "Rails console"},
          {["sidekiq", "-C", private], "Sidekiq"},
          {["puma", "-p", private], "Puma"}
        ] do
      assert {:error, reason} = Command.native(argv, @prod)
      assert reason =~ label
    end

    for env <- [%{"PORT" => private}, %{"BINDING" => private}] do
      assert {:error, reason} = Command.native(~w(dawarich start), env)
      refute reason =~ private
    end

    assert Command.native(~w(rails server -p=5000 -b=::), @prod) == {:web, {@any6, 5000}}
  end

  test "legacy Sidekiq and migrate argv map to native roles without extra jobs runtime" do
    for prefix <- [[], ~w(bundle exec)],
        config <- [
          [],
          ~w(-C config/sidekiq.yml),
          ~w(--config=config/sidekiq.yml),
          ~w(-Cconfig/sidekiq.yml)
        ] do
      assert Command.native(prefix ++ ["sidekiq"] ++ config, @prod) == :sidekiq_idle
    end

    for prefix <- [[], ~w(bundle exec)], rails <- ~w(rails bin/rails) do
      assert Command.native(prefix ++ [rails, "db:migrate"], @prod) == :migrate
      assert Command.native(prefix ++ [rails, "db:seed"], @prod) == :seeds
    end

    assert Command.native(~w(dawarich start), %{"PORT" => "5000", "BINDING" => "::"}) ==
             {:web, {@any6, 5000}}

    assert Command.native(~w(dawarich migrate), @prod) == :migrate
    assert Command.native(~w(dawarich seeds), @prod) == :seeds

    for args <- [
          ~w(help),
          ~w(migrate status),
          ~w(jobs drain-status),
          ["users", "email", "old name", "new name"]
        ] do
      assert Command.native(["dawarich" | args], @prod) == {:cli, args}
      assert {:ok, _, _} = Dawarich.CLI.resolve(args)
    end

    for args <- [["eval", "IO.puts(1)"], ["rpc", "IO.puts(1)"], ["remote"]] do
      assert Command.native(["dawarich" | args], @prod) == {:release, args}
    end

    assert Dawarich.Application.children(:sidekiq_idle) == []
  end

  test "native puma parsing maps known Procfiles and refuses custom configurations" do
    for prefix <- [[], ~w(bundle exec)],
        config <- [[], ~w(-C config/puma.rb), ~w(--config=config/puma.rb), ~w(-Cconfig/puma.rb)] do
      assert Command.native(prefix ++ ["puma"] ++ config, @prod) == {:web, {@any4, 3000}}

      assert Command.native(prefix ++ ["puma"] ++ config ++ ~w(-p 5000), @prod) ==
               {:web, {@any4, 5000}}
    end

    assert Command.native(~w(puma -C config/puma.rb), %{"PORT" => "4100", "BINDING" => "::"}) ==
             {:web, {@any6, 4100}}

    for bind <- [~w(-b tcp://[::]:5000), ~w(--bind=tcp://[::]:5000), ~w(-btcp://[::]:5000)] do
      assert Command.native(["puma" | bind], @prod) == {:web, {@any6, 5000}}
    end

    for args <- [
          ~w(-C config/custom.rb),
          ~w(-C config/custom.rb -p 5000),
          ~w(-C config/custom.rb -b tcp://127.0.0.1:5000),
          ~w(-C config/puma.rb -C config/puma.rb),
          ~w(-b tcp://127.0.0.1:5000 -b tcp://127.0.0.1:5001),
          ~w(-p 5000 -p 5001),
          ~w(-p 5000 -b tcp://127.0.0.1:5001),
          ~w(-w 2),
          ~w(-b unix:///tmp/native.sock)
        ] do
      assert {:error, _} = Command.native(["puma" | args], @prod)
    end
  end

  test "native server parsing preserves compose IPv6 binding and port with optional bundle exec" do
    for prefix <- [[], ~w(bundle exec)],
        rails <- ~w(rails bin/rails),
        server <- ~w(server s),
        flags <- [
          ~w(-p 3000 -b ::),
          ~w(--port 3000 --binding ::),
          ~w(--port=3000 --binding=::),
          ~w(-p3000 -b::)
        ] do
      assert Command.native(prefix ++ [rails, server] ++ flags, @prod) == {:web, {@any6, 3000}}
    end

    assert Command.native(~w(rails server), @prod) == {:web, {@any4, 3000}}
    assert Command.native(~w(rails server), %{}) == {:web, {{127, 0, 0, 1}, 3000}}

    assert Command.native(~w(rails server), %{"PORT" => "4100", "BINDING" => "10.0.0.5"}) ==
             {:web, {{10, 0, 0, 5}, 4100}}

    assert Command.native(~w(rails server -p 3001 -p 3002), @prod) == {:web, {@any4, 3002}}
  end
end
