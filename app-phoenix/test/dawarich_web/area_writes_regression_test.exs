defmodule DawarichWeb.AreaWritesRegressionTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Plug.Test
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{AreaActions, MapWriteRequest, RailsAuth, RailsCsrf}

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    user = FrameSeeds.user!(88101, %{"timezone" => "UTC"}, %{plan: 0, status: 0})
    Ownership.put!(Repo, "command:areas.relabel_visits", :oban)
    %{user: user, session: RailsUser.session(user.id), now: ~U[2026-10-03 10:00:00.000000Z]}
  end

  @tag area_numeric: true
  test "area create and update preserve Rails numericality and separate attribute casts", ctx do
    for {input, radius} <- [
          {"1e2", 1},
          {".5", 0},
          {"1.", 1},
          {"1_0", 10},
          {"200.5", 200},
          {"+20", 20},
          {" 20 ", 20}
        ] do
      attrs = %{"name" => "Synthetic", "latitude" => "51", "longitude" => "12", "radius" => input}
      assert_flash(request(ctx, :post, "/areas", attrs), "Area created successfully!")
      [[id, ^radius]] = Repo.query!("SELECT id,radius FROM areas ORDER BY id DESC LIMIT 1").rows

      for method <- [:patch, :put] do
        Repo.query!("UPDATE areas SET radius=300 WHERE id=$1", [id])
        assert_flash(request(ctx, method, "/areas/#{id}", attrs), "Area updated successfully!")
        assert Repo.query!("SELECT radius FROM areas WHERE id=$1", [id]).rows == [[radius]]
      end
    end

    for {input, expected} <- [
          {".5", "0.500000"},
          {"1.", "1.000000"},
          {"1_0", "10.000000"},
          {"5.1e1", "51.000000"}
        ] do
      attrs = %{
        "name" => "Synthetic",
        "latitude" => input,
        "longitude" => input,
        "radius" => "200"
      }

      assert_flash(request(ctx, :post, "/areas", attrs), "Area created successfully!")
      [[id]] = Repo.query!("SELECT id FROM areas ORDER BY id DESC LIMIT 1").rows

      for method <- [:patch, :put] do
        Repo.query!("UPDATE areas SET latitude=0,longitude=0 WHERE id=$1", [id])
        assert_flash(request(ctx, method, "/areas/#{id}", attrs), "Area updated successfully!")

        assert Repo.query!("SELECT latitude::text,longitude::text FROM areas WHERE id=$1", [id]).rows ==
                 [[expected, expected]]
      end
    end

    for {input, error} <- [
          {"0x10", "Radius is not a number"},
          {"1__0", "Radius is not a number"},
          {"1e", "Radius is not a number"},
          {"NaN", "Radius is not a number"},
          {"0", "Radius must be greater than 0"},
          {"-1", "Radius must be greater than 0"}
        ] do
      before = Repo.query!("SELECT * FROM areas ORDER BY id").rows
      [[id]] = Repo.query!("SELECT id FROM areas ORDER BY id DESC LIMIT 1").rows
      attrs = %{"name" => "Synthetic", "latitude" => "51", "longitude" => "12", "radius" => input}

      for {method, path} <- [{:post, "/areas"}, {:patch, "/areas/#{id}"}, {:put, "/areas/#{id}"}] do
        assert_flash(request(ctx, method, path, attrs), error)
        assert Repo.query!("SELECT * FROM areas ORDER BY id").rows == before
      end
    end
  end

  @tag area_retry: true
  test "rounding-equivalent area retries preserve timestamps and relabel work after consumption",
       ctx do
    attrs = %{"name" => "Synthetic", "latitude" => "51", "longitude" => "12", "radius" => "200"}

    for edit <- [
          %{"radius" => "200.5"},
          %{"latitude" => "51.0000004"},
          %{"longitude" => "12.0000004"}
        ] do
      Repo.query!("DELETE FROM public.job_outbox")
      assert_flash(request(ctx, :post, "/areas", attrs), "Area created successfully!")
      [[id]] = Repo.query!("SELECT id FROM areas ORDER BY id DESC LIMIT 1").rows
      before = Repo.query!("SELECT * FROM areas WHERE id=$1", [id]).rows
      pending = Repo.query!("SELECT * FROM public.job_outbox").rows
      assert length(pending) == 1

      for {method, seconds} <- [{:patch, 1}, {:put, 2}] do
        retry = %{ctx | now: DateTime.add(ctx.now, seconds)}
        assert_flash(request(retry, method, "/areas/#{id}", edit), "Area updated successfully!")
        assert Repo.query!("SELECT * FROM areas WHERE id=$1", [id]).rows == before

        if seconds == 1 do
          assert Repo.query!("SELECT * FROM public.job_outbox").rows == pending
          Repo.query!("DELETE FROM public.job_outbox")
        else
          assert Repo.query!("SELECT * FROM public.job_outbox").rows == []
        end
      end

      renamed = %{ctx | now: DateTime.add(ctx.now, 3)}

      assert_flash(
        request(renamed, :patch, "/areas/#{id}", %{"name" => "Renamed"}),
        "Area updated successfully!"
      )

      assert Repo.query!("SELECT name,updated_at FROM areas WHERE id=$1", [id]).rows == [
               ["Renamed", DateTime.to_naive(renamed.now)]
             ]

      assert Repo.query!("SELECT * FROM public.job_outbox").rows == []

      reshaped = %{ctx | now: DateTime.add(ctx.now, 4)}

      assert_flash(
        request(reshaped, :patch, "/areas/#{id}", %{
          "latitude" => "51.0000005",
          "longitude" => "-12.0000005"
        }),
        "Area updated successfully!"
      )

      assert Repo.query!(
               "SELECT latitude::text,longitude::text,updated_at FROM areas WHERE id=$1",
               [id]
             ).rows == [["51.000001", "-12.000001", DateTime.to_naive(reshaped.now)]]

      assert [[%{"area_id" => ^id}]] = Repo.query!("SELECT payload FROM public.job_outbox").rows
    end
  end

  defp request(ctx, method, path, attrs, accept \\ "text/vnd.turbo-stream.html") do
    raw =
      URI.encode_query(Map.put(attrs, "authenticity_token", RailsCsrf.masked_token(ctx.session)))

    conn =
      method
      |> conn(path, raw)
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> put_req_header("accept", accept)
      |> RailsAuth.call([])
      |> MapWriteRequest.call([])
      |> assign(:now, ctx.now)

    if conn.halted, do: conn, else: AreaActions.call(conn, :write)
  end

  defp assert_flash(response, text) do
    assert response.status == 200

    assert get_resp_header(response, "content-type") == [
             "text/vnd.turbo-stream.html; charset=utf-8"
           ]

    assert response.resp_body =~ ~s(<turbo-stream action="append" target="flash-messages">)

    assert response.resp_body
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("turbo-stream")
           |> LazyHTML.text()
           |> String.trim() == text
  end
end
