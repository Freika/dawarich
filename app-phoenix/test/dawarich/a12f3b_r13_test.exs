defmodule Dawarich.A12f3bR13Test do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.ReversePlaceWorker
  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsEffects

  setup do
    saved = System.get_env("DAWARICH_RAILS")

    on_exit(fn ->
      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag a12f3b_case: "R13k05"
  test "reverse_geocode_place native producer reaches its source terminal effect" do
    for {mode, owner} <- [{"on", :oban}, {"off", :oban}, {"off", :sidekiq}] do
      Dawarich.JobsCase.reset!(ScratchRepo)
      clear_response_cache!()
      System.put_env("DAWARICH_RAILS", mode)
      Ownership.put!(ScratchRepo, "command:geocoding.reverse_place", owner)
      f = load!("place_name_locked")
      stub_requests!(f["requests"])
      user = hd(f["input"]["users"])["id"]
      place = f["place_id"]

      assert RailsEffects.reverse_place(ScratchRepo, user, place) == :ok
      assert Dawarich.JobsCase.rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

      assert [["Dawarich.Geocoding.ReversePlaceWorker", args]] =
               Dawarich.JobsCase.rows("SELECT worker,args FROM oban.oban_jobs")

      assert args == %{"place_id" => place}
      assert ReversePlaceWorker.perform(%Oban.Job{args: args}) == :ok
      assert ReversePlaceWorker.perform(%Oban.Job{args: args}) == :ok
      expected = hd(f["expected"]["places"])

      assert Dawarich.JobsCase.rows(
               "SELECT name,city,country,name_locked_at IS NOT NULL,reverse_geocoded_at IS NOT NULL FROM places WHERE id=$1",
               [place]
             ) == [[expected["name"], expected["city"], expected["country"], true, true]]

      assert Dawarich.JobsCase.rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    end

    Dawarich.JobsCase.reset!(ScratchRepo)
    System.put_env("DAWARICH_RAILS", "on")
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_place", :sidekiq)
    assert RailsEffects.reverse_place(ScratchRepo, 7, 9) == :ok

    assert Dawarich.JobsCase.rows("SELECT kind,payload FROM phoenix.rails_commands") ==
             [["reverse_geocode_place", %{"user_id" => 7, "place_id" => 9}]]

    assert Dawarich.JobsCase.rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end
end
