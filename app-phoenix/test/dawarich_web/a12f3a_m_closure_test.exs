defmodule DawarichWeb.A12f3aMClosureTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{MapWindow, Repo}
  alias Dawarich.Test.{FrameSeeds, ParityHTML, RailsUser}
  alias DawarichWeb.{MapFrames, MapFramesGate}
  @endpoint DawarichWeb.Endpoint
  @frame "text/html, application/xhtml+xml"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(SELF_HOSTED MANAGER_URL JWT_SECRET_KEY), &{&1, System.get_env(&1)})
    System.put_env("MANAGER_URL", "https://manager.example.test")
    System.put_env("JWT_SECRET_KEY", "synthetic-map-closure-test-secret")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    :ok
  end

  @tag a12f3a_m01: true
  test "M01: map shell selection and legacy settings matches current Rails contract without a native-owner Rails effect" do
    capture = load("m01")
    {:ok, now, 0} = DateTime.from_iso8601(capture["now"])
    settings = capture["settings"]
    env = Map.reject(capture["env"], fn {_, v} -> is_nil(v) end)
    user = FrameSeeds.user!(89001, settings)

    for mode <- ["true", "false", nil] do
      self_hosted(mode)

      for row <- capture["cases"] do
        window = MapWindow.build(row["params"], settings, now, nil, env)

        for key <- ~w(start end iana start_local end_local) do
          assert Map.fetch!(window, String.to_existing_atom(key)) == row["expected"][key]
        end

        assert window.calendar_month == row["expected"]["calendar"]

        for path <- [row["path"], String.replace(row["path"], "/map/v2", "/map")] do
          conn = RailsUser.signed_in(user.id) |> get(path)
          assert conn.status == 200
          for marker <- load("m07")["markers"], do: assert(conn.resp_body =~ ~s(id="#{marker}"))
          assert conn.resp_body =~ row["expected"]["start"]
          assert head(RailsUser.signed_in(user.id), path).resp_body == ""
        end
      end

      assert redirected_to(get(build_conn(), "/map")) == "http://www.example.com/users/sign_in"
    end

    assert effects() == {0, 0}
  end

  @tag a12f3a_m02: true
  test "M02: legacy map redirects matches current Rails contract without a native-owner Rails effect" do
    user = FrameSeeds.user!(89002)

    for mode <- ["true", "false", nil] do
      self_hosted(mode)

      for row <- load("m02")["cases"], signed <- [true, false] do
        conn = if signed, do: RailsUser.signed_in(user.id), else: build_conn()

        conn =
          if row["method"] == "head", do: head(conn, row["path"]), else: get(conn, row["path"])

        assert conn.status == row["status"]
        assert get_resp_header(conn, "location") == [row["location"]]
        assert conn.resp_body == row["body"]
      end
    end

    assert effects() == {0, 0}
  end

  defp effects do
    {Repo.query!("SELECT count(*) FROM public.job_outbox", []).rows |> hd() |> hd(),
     Dawarich.ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs", []).rows |> hd() |> hd()}
  end

  defp load(name),
    do: "test/fixtures/map_frames/a12f3a-#{name}.json" |> File.read!() |> Jason.decode!()

  defp self_hosted(nil), do: System.delete_env("SELF_HOSTED")
  defp self_hosted(mode), do: System.put_env("SELF_HOSTED", mode)
end
