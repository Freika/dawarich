defmodule Dawarich.Cable.ChannelsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Cable.Channels
  alias Dawarich.RailsMessages
  alias Dawarich.Test.A12a

  setup do
    A12a.seed!()
    :ok
  end

  defp context(self_hosted \\ true),
    do: %{secret: A12a.secret(), now: &A12a.now/0, self_hosted: self_hosted}

  defp alice, do: %{user: A12a.user!("alice"), share: nil}
  defp share_only, do: %{user: nil, share: A12a.share!("live_open")}

  test "user channels stream the user's broadcasting and reject a share-only connection" do
    id = alice().user.id

    for {name, channel} <- [
          {"PointsChannel", "points"},
          {"TracksChannel", "tracks"},
          {"ImportsChannel", "imports"},
          {"MapEditsChannel", "map_edits"}
        ] do
      assert Channels.authorize(%{"channel" => name}, alice(), context()) ==
               {:stream, RailsMessages.broadcasting([channel, {:user, id}])}

      assert Channels.authorize(%{"channel" => name}, share_only(), context()) == :reject
    end
  end

  test "family locations need the families feature and a membership" do
    bob = %{user: A12a.user!("bob"), share: nil}
    family = A12a.family_id!("bob")

    assert Channels.authorize(%{"channel" => "FamilyLocationsChannel"}, bob, context()) ==
             {:stream, RailsMessages.broadcasting(["family_locations", {:family, family}])}

    assert Channels.authorize(%{"channel" => "FamilyLocationsChannel"}, alice(), context()) ==
             :reject

    assert Channels.authorize(%{"channel" => "FamilyLocationsChannel"}, bob, context(false)) ==
             :reject
  end

  test "shared location streams only the connection's own share, compared as a string" do
    id = share_only().share.id
    params = %{"channel" => "SharedLocationChannel", "share_id" => id}

    assert Channels.authorize(params, share_only(), context()) ==
             {:stream, RailsMessages.broadcasting(["shared_location", {:shared_link, id}])}

    upper = %{params | "share_id" => String.upcase(id)}
    assert Channels.authorize(upper, share_only(), context()) == :reject
    assert Channels.authorize(%{params | "share_id" => 1}, share_only(), context()) == :reject
    assert Channels.authorize(params, alice(), context()) == :reject
  end

  test "Turbo streams need a verified name; ApplicationCable::Channel confirms; unknown names are ignored" do
    signed = RailsMessages.stream_name([{:user, alice().user.id}, "notifications"], A12a.secret())
    turbo = &%{"channel" => "Turbo::StreamsChannel", "signed_stream_name" => &1}

    assert Channels.authorize(turbo.(signed), share_only(), context()) ==
             {:stream, RailsMessages.broadcasting([{:user, alice().user.id}, "notifications"])}

    assert Channels.authorize(turbo.(signed <> "0"), alice(), context()) == :reject

    assert Channels.authorize(%{"channel" => "Turbo::StreamsChannel"}, alice(), context()) ==
             :reject

    assert Channels.authorize(turbo.(5), alice(), context()) ==
             A12a.expected_decision("turbo_number")

    assert Channels.authorize(%{"channel" => "ApplicationCable::Channel"}, alice(), context()) ==
             :confirm

    assert Channels.authorize(%{"channel" => "NopeChannel"}, alice(), context()) == :ignore

    for name <- A12a.corpus()["names"]["resolved"],
        do: refute(Channels.authorize(%{"channel" => name}, alice(), context()) == :ignore, name)

    for name <- A12a.corpus()["names"]["unresolved"],
        do: assert(Channels.authorize(%{"channel" => name}, alice(), context()) == :ignore, name)
  end
end
