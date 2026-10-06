defmodule DawarichWeb.TimelineShareRoutes do
  @moduledoc false
  defmacro routes do
    quote do
      scope "/share_links/timeline" do
        pipe_through :rails_frame

        get "/new", DawarichWeb.TimelineShareActions, :new,
          metadata: %{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}
      end

      scope "/share_links/timeline" do
        pipe_through :share_form

        for {verb, suffix, action} <- [
              {:post, "/", :create},
              {:delete, "/", :destroy},
              {:patch, "/revoke", :revoke},
              {:post, "/revoke", :revoke},
              {:post, "/regenerate", :regenerate},
              {:post, "/regenerate_phrase", :regenerate_phrase}
            ] do
          match verb, suffix, DawarichWeb.TimelineShareActions, action,
            metadata: %{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}
        end
      end
    end
  end
end
