defmodule Dawarich.Mail.Layout do
  @moduledoc false
  require EEx

  @dir Path.expand("../../../priv/mail", __DIR__)

  for file <- ~w(layout.html layout.text) do
    @external_resource Path.join(@dir, file <> ".eex")
  end

  EEx.function_from_file(:def, :html, Path.join(@dir, "layout.html.eex"), [:locale, :inner])
  EEx.function_from_file(:def, :text, Path.join(@dir, "layout.text.eex"), [:inner])
end
