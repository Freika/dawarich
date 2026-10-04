defmodule DawarichWeb.AuthCommonPipelineTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias DawarichWeb.{ForceSSL, HostAuthorization, RateLimit}

  test "account and key handlers limit immediately after SSL before admission and respect halts" do
    previous = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")
    owner = self()
    tracer = spawn(fn -> trace_calls(owner) end)
    modules = [HostAuthorization, ForceSSL, RateLimit]

    for module <- modules do
      Code.ensure_loaded!(module)
      :erlang.trace_pattern({module, :call, 2}, true, [:local])
    end

    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    on_exit(fn ->
      for module <- modules, do: :erlang.trace_pattern({module, :call, 2}, false, [:local])
      Process.exit(tracer, :kill)

      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    for {handler, method, path} <- [
          {DawarichWeb.AuthAccount.Http, "PATCH", "/users"},
          {DawarichWeb.AuthApiKeys.Http, "POST", "/settings/generate_api_key"}
        ] do
      input = Plug.Test.conn(method, "http://www.example.com" <> path, "retained=bytes")

      result =
        handler.call(input,
          enabled: true,
          context: %{secret: nil, self_hosted: true, oidc: false},
          fallback: fn conn ->
            assert conn.private[:dawarich_rate_limit] == []
            send(owner, :admitted)
            conn
          end
        )

      barrier(tracer)
      assert pipeline_calls() == [HostAuthorization, ForceSSL, RateLimit]
      assert_received :admitted
      assert result.halted
      assert {:ok, "retained=bytes", _} = read_body(result)

      System.put_env("APPLICATION_PROTOCOL", "https")
      System.put_env("RAILS_ENV", "production")

      result = handler.call(input, enabled: true, fallback: fn _ -> flunk("SSL must halt") end)
      assert result.status == 308 and result.halted
      barrier(tracer)
      assert pipeline_calls() == [HostAuthorization, ForceSSL]
      refute_received :admitted
      System.put_env("APPLICATION_PROTOCOL", "http")
      System.put_env("RAILS_ENV", "test")
    end

    :erlang.trace(self(), false, [:call])
  end

  defp barrier(tracer) do
    ref = :erlang.trace_delivered(self())
    assert_receive {:trace_delivered, _, ^ref}
    send(tracer, {:barrier, ref})
    assert_receive {:barrier, ^ref}
  end

  defp trace_calls(owner) do
    receive do
      {:trace, _, :call, {module, :call, _}} ->
        send(owner, {:pipeline_call, module})
        trace_calls(owner)

      {:barrier, ref} ->
        send(owner, {:barrier, ref})
        trace_calls(owner)
    end
  end

  defp pipeline_calls(acc \\ []) do
    receive do
      {:pipeline_call, module} -> pipeline_calls([module | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
