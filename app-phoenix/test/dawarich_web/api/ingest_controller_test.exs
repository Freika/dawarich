defmodule DawarichWeb.Api.IngestControllerTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog

  alias DawarichWeb.Api.IngestController

  @moduletag :capture_log

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    %{upstream: upstream}
  end

  defp with_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log([level: :info], fun)
    after
      Logger.configure(level: previous)
    end
  end

  test "a non-Unsupported prepare exception terminates locally without leaking its message",
       %{upstream: upstream} do
    user = user!()

    conn =
      conn(:post, "/api/v1/points")
      |> assign(:api_params, [52.9, 13.4])
      |> assign(:api_user, %{id: user})
      |> assign(:api_tag, "ingest")

    log =
      with_info_log(fn ->
        result = IngestController.call(conn, :points)
        assert result.status == 422
        assert Jason.decode!(result.resp_body) == %{"error" => "Unprocessable Entity"}
        assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
        assert result.halted
      end)

    assert log =~ ~s("reason":"api_body")
    refute log =~ "FunctionClauseError"
    refute log =~ "no function clause matching"
  end

  test "an Unsupported prepare exception terminates locally without exposing its reason", %{
    upstream: upstream
  } do
    user = user!()

    body =
      ~s({"locations":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"timestamp":1790000000,"battery_level":true}}]})

    conn =
      conn(:post, "/api/v1/points")
      |> assign(:api_params, Jason.decode!(body))
      |> assign(:api_user, %{id: user})
      |> assign(:api_tag, "ingest")

    log =
      with_info_log(fn ->
        result = IngestController.call(conn, :points)
        assert result.status == 422
        assert Jason.decode!(result.resp_body) == %{"error" => "Unprocessable Entity"}
        assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
        assert result.halted
      end)

    assert log =~ ~s("reason":"api_body")
    refute log =~ "to_f of a non-number"
  end
end
