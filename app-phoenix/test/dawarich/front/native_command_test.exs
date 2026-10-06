defmodule Dawarich.Front.NativeCommandTest do
  use ExUnit.Case, async: true

  alias Dawarich.Front.Command

  @prod %{"RAILS_ENV" => "production"}
  @any4 {0, 0, 0, 0}
  @any6 {0, 0, 0, 0, 0, 0, 0, 0}

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
