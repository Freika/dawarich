defmodule Dawarich.Auth.AccountLink.PendingTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.AccountLink.Pending
  alias Dawarich.{Auth.Account, Repo}
  alias Dawarich.Test.RailsUser

  @source "test/fixtures/auth/account_link/requests.json" |> File.read!() |> Jason.decode!()
  @excluded "test/fixtures/auth/account_link/exclusions.json" |> File.read!() |> Jason.decode!()
  @now @source["at"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  defp insert_actor(state) do
    attrs = %{
      id: state["id"],
      email: state["email"],
      encrypted_password: state["encrypted_password"],
      settings: state["settings"],
      provider: state["provider"],
      uid: state["uid"],
      status: status(state["status"]),
      otp_required_for_login: state["otp_required_for_login"],
      failed_attempts: state["failed_attempts"],
      failed_otp_attempts: state["failed_otp_attempts"],
      sign_in_count: state["sign_in_count"],
      locked_at: stamp(state["locked_at"]),
      deleted_at: stamp(state["deleted_at"])
    }

    RailsUser.insert!(attrs)
  end

  defp stamp(nil), do: nil
  defp stamp(value), do: value |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()
  defp status(value) when is_integer(value), do: value

  defp status(value),
    do: Map.fetch!(%{"inactive" => 0, "active" => 1, "trial" => 2, "pending_payment" => 3}, value)

  test "pending identity admits only source-shaped OIDC collision targets at inclusive expiry" do
    assert Code.ensure_loaded?(Pending)
    context = %{self_hosted: true, oidc: true, remember: false}

    for name <- ~w(challenge_en challenge_de challenge_fr) do
      oracle = @source[name]
      insert_actor(oracle["before"])
      before = Repo.get!(Account, oracle["before"]["id"])
      session = oracle["session"]
      assert {:ok, prepared} = Pending.valid(session, @now, context)
      assert prepared.user.id == before.id
      assert prepared.pending == session["pending_oauth_link"]
      assert prepared.session == session
      assert prepared.user.uid == nil
      assert prepared.user.settings == %{}
      assert Repo.get!(Account, before.id) == before
      refute Map.has_key?(session, "warden.user.user.key")
    end

    for {name, oracle} <- @excluded do
      state = oracle["confirmation"]["before"]
      insert_actor(state)
      session = oracle["challenge"]["session"] |> Map.put("pending_oauth_link", oracle["pending"])
      snapshot = Repo.get!(Account, state["id"])

      if oracle["native"] do
        assert {:ok, prepared} = Pending.valid(session, @now, context), name
        assert prepared.user.id == state["id"]
      else
        assert {:handoff, _} = Pending.valid(session, @now, context), name
      end

      assert Repo.get!(Account, state["id"]) == snapshot
    end

    oracle = @source["otp"]
    insert_actor(oracle["before"])
    pending = @source["challenge_en"]["session"]["pending_oauth_link"]
    session = %{"pending_oauth_link" => Map.put(pending, "user_id", oracle["before"]["id"])}
    assert {:ok, %{user: %{otp_required_for_login: true}}} = Pending.valid(session, @now, context)

    for unsupported <- [nil, false, [], "pending", %{}, Map.put(pending, "extra", true)] do
      assert {:handoff, _} = Pending.valid(%{"pending_oauth_link" => unsupported}, @now, context)
    end

    for {key, values} <- [
          {"user_id", [nil, "42", -1, true, 9_999_999_999_999_999_999]},
          {"expires_at", [nil, "1791201600", 1.0, [], 999_999_999_999_999_999]},
          {"uid", [nil, "", [], <<0>>]},
          {"provider_label", [false, [], %{}]},
          {"provider", [nil, "google", "apple"]}
        ],
        value <- values do
      changed = put_in(session, ["pending_oauth_link", key], value)
      assert {:handoff, _} = Pending.valid(changed, @now, context)
    end

    for extra <- [
          %{"pending_import_ticket" => "synthetic"},
          %{"otp_user_id" => 42},
          %{"warden.user.user.key" => [[42], "synthetic"]},
          %{"client" => "mobile"},
          %{"referral" => "synthetic"},
          %{"invitation_token" => "synthetic"}
        ] do
      assert {:handoff, _} = Pending.valid(Map.merge(session, extra), @now, context)
    end

    assert {:handoff, _} = Pending.valid(session, @now, %{context | self_hosted: false})
    assert {:handoff, _} = Pending.valid(session, @now, %{context | remember: true})

    for label <- [nil, "", "<script>synthetic</script>"] do
      changed = put_in(session, ["pending_oauth_link", "provider_label"], label)
      assert {:ok, _} = Pending.valid(changed, @now, context)
    end

    assert :uid in Account.__schema__(:redact_fields)
  end
end
