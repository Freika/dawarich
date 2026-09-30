defmodule DawarichWeb.StranglerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias DawarichWeb.Strangler

  def boom(_conn, _params), do: exit(:timeout)

  test "a rails_gate that is not a {module, function} tuple fails closed" do
    route = %{rails_gate: &Kernel.is_nil/1, path_params: %{}}
    refute Strangler.gate_open?(route, %Plug.Conn{})
  end

  test "an exit from the gate hands the request to Puma" do
    route = %{rails_gate: {__MODULE__, :boom}, path_params: %{}}
    conn = %Plug.Conn{request_path: "/trips"}

    Logger.put_module_level(Strangler, :info)
    on_exit(fn -> Logger.delete_module_level(Strangler) end)

    log =
      capture_log(fn ->
        refute Strangler.gate_open?(route, conn)
      end)

    assert log =~ "[strangler] /trips handed to Rails: :timeout"
  end
end
