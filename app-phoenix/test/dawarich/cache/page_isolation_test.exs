defmodule Dawarich.Cache.PageIsolationTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Accounts.Scope
  alias Dawarich.Cache.Pages
  alias Dawarich.Test.{FrameSeeds, NativePageCache}

  test "two owners and two locale unit zone choices never share private data" do
    {:ok, cache} = NativePageCache.start()
    opts = NativePageCache.options(cache)
    first = Scope.for_user(FrameSeeds.user!(8821, %{"timezone" => "UTC"}), "en")
    other = Scope.for_user(FrameSeeds.user!(8822, %{"timezone" => "UTC"}), "en")

    reader = fn scope ->
      {:ok,
       %{
         owner: scope.user.id,
         locale: scope.locale,
         unit: Dawarich.Analytics.Period.unit(scope.user.settings),
         zone: Dawarich.UserTimeZone.iana(Repo, scope.user.settings)
       }}
    end

    assert {:ok, %{owner: 8821}} = Pages.fetch(first, :summary, %{}, reader, opts)
    assert {:ok, %{owner: 8822}} = Pages.fetch(other, :summary, %{}, reader, opts)

    assert {:ok, %{locale: "de"}} =
             Pages.fetch(%{first | locale: "de"}, :summary, %{}, reader, opts)

    Repo.query!(
      "UPDATE users SET settings=$2 WHERE id=$1",
      [first.user.id, %{"timezone" => "Europe/Berlin"}],
      log: false
    )

    assert {:ok, %{zone: "Europe/Berlin", unit: "km"}} =
             Pages.fetch(first, :summary, %{}, reader, opts)

    Repo.query!(
      "UPDATE users SET settings=$2 WHERE id=$1",
      [first.user.id, %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "mi"}}],
      log: false
    )

    assert {:ok, %{unit: "mi"}} = Pages.fetch(first, :summary, %{}, reader, opts)
    assert map_size(NativePageCache.entries(cache)) == 5
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [first.user.id], log: false)

    assert {:ok, _} =
             Pages.fetch(first, :summary, %{}, reader, Keyword.put(opts, :self_hosted, false))

    assert map_size(NativePageCache.entries(cache)) == 6
  end

  test "disabled or expired public share refuses a warmed cache" do
    {:ok, cache} = NativePageCache.start()
    scope = Scope.for_user(FrameSeeds.user!(8831, %{"timezone" => "UTC"}), "en")
    uuid = Ecto.UUID.generate()
    now = NativePageCache.now(cache)

    settings = %{
      "enabled" => true,
      "expiration" => "1h",
      "expires_at" => DateTime.from_unix!(now + 3600) |> DateTime.to_iso8601()
    }

    Dawarich.Test.StatsSeeds.stat!(scope.user.id, %{
      year: 2025,
      month: 3,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: settings
    })

    authorize = fn fresh, clock ->
      case rows("SELECT sharing_settings FROM stats WHERE user_id=$1 AND sharing_uuid=$2", [
             fresh.user.id,
             Ecto.UUID.dump!(uuid)
           ]) do
        [[settings]] ->
          if Dawarich.Digests.Sharing.public?(settings, DateTime.from_unix!(clock), "UTC"),
            do: :ok,
            else: {:error, :unauthorized}

        _ ->
          {:error, :unauthorized}
      end
    end

    opts = NativePageCache.options(cache) ++ [audience: {:public, uuid}, authorize: authorize]
    reader = fn _ -> {:ok, %{distance: 42}} end
    assert {:ok, %{distance: 42}} = Pages.fetch(scope, :summary, %{}, reader, opts)
    assert map_size(NativePageCache.entries(cache)) == 1

    Repo.query!(
      "UPDATE stats SET sharing_settings=jsonb_set(sharing_settings,'{enabled}','false') WHERE user_id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :unauthorized} = Pages.fetch(scope, :summary, %{}, reader, opts)

    Repo.query!(
      "UPDATE stats SET sharing_settings=jsonb_set(sharing_settings,'{enabled}','true') WHERE user_id=$1",
      [scope.user.id],
      log: false
    )

    NativePageCache.advance(cache, 3601)
    assert {:error, :unauthorized} = Pages.fetch(scope, :summary, %{}, reader, opts)

    assert {:error, :unauthorized} =
             Pages.fetch(scope, :summary, %{}, reader, Keyword.delete(opts, :authorize))
  end

  for {boundary, operation} <- [{:miss, "SET"}, {:hit, "GET"}],
      change <- [:revocation, :expiry] do
    @tag review_delivery: true
    @tag cache_return: true
    if boundary == :hit do
      @tag cache_hit: true
    end

    test "public cache #{boundary} refuses #{change} during #{operation}" do
      {:ok, cache} = NativePageCache.start()
      scope = Scope.for_user(FrameSeeds.user!(8832, %{"timezone" => "UTC"}), "en")
      uuid = Ecto.UUID.generate()
      now = NativePageCache.now(cache)

      settings = %{
        "enabled" => true,
        "expiration" => "1h",
        "expires_at" => DateTime.from_unix!(now + 3600) |> DateTime.to_iso8601()
      }

      Dawarich.Test.StatsSeeds.stat!(scope.user.id, %{
        year: 2025,
        month: 3,
        sharing_uuid: Ecto.UUID.dump!(uuid),
        sharing_settings: settings
      })

      authorize = fn fresh, clock ->
        [[settings]] =
          rows("SELECT sharing_settings FROM stats WHERE user_id=$1 AND sharing_uuid=$2", [
            fresh.user.id,
            Ecto.UUID.dump!(uuid)
          ])

        if Dawarich.SharingExpiry.public?(settings, DateTime.from_unix!(clock), "UTC"),
          do: :ok,
          else: {:error, :unauthorized}
      end

      command = fn args ->
        result = NativePageCache.command(cache, args)

        if hd(args) == unquote(operation) do
          case unquote(change) do
            :revocation ->
              rows("UPDATE stats SET sharing_settings='{}' WHERE user_id=$1", [scope.user.id])

            :expiry ->
              NativePageCache.advance(cache, 3601)
          end
        end

        result
      end

      opts = NativePageCache.options(cache) ++ [audience: {:public, uuid}, authorize: authorize]

      if unquote(boundary) == :hit do
        assert {:ok, %{distance: 42}} =
                 Pages.fetch(scope, :summary, %{}, fn _ -> {:ok, %{distance: 42}} end, opts)
      end

      reader = fn _ ->
        if unquote(boundary) == :hit, do: flunk("a warmed hit recomputed its value")
        {:ok, %{distance: 42}}
      end

      assert {:error, :unauthorized} =
               Pages.fetch(scope, :summary, %{}, reader, Keyword.put(opts, :command, command))

      assert Enum.any?(NativePageCache.commands(cache), &match?(["SET" | _], &1))
      if unquote(boundary) == :miss, do: assert(NativePageCache.entries(cache) == %{})
    end
  end
end
