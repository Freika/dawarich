defmodule Dawarich.Test.Await do
  @moduledoc false

  @max_receive_timeout 4_294_967_295

  defmacro await_receive(pattern) do
    quote do
      ExUnit.Assertions.assert_receive(unquote(pattern), unquote(@max_receive_timeout))
    end
  end
end
