defmodule DawarichWeb.TrackShareRoutes do
  @moduledoc false
  defmacro routes do
    quote do
      scope "/tracks/:track_id/share_link" do
        pipe_through :rails_frame

        get "/new", DawarichWeb.TrackShareActions, :new,
          metadata: %{rails_gate: {DawarichWeb.TrackShareActions, :native?}}
      end

      scope "/tracks/:track_id/share_link" do
        pipe_through :share_form

        for {verb, suffix, action} <- [
              {:post, "", :create},
              {:delete, "", :destroy},
              {:patch, "/revoke", :revoke},
              {:post, "/regenerate", :regenerate},
              {:post, "/regenerate_phrase", :regenerate_phrase}
            ] do
          match verb, suffix, DawarichWeb.TrackShareActions, action,
            metadata: %{rails_gate: {DawarichWeb.TrackShareActions, :native?}}
        end
      end
    end
  end
end
