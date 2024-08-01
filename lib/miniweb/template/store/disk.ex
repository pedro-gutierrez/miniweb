defmodule Miniweb.Template.Store.Disk do
  @moduledoc """
  A builder that gives you a store that reads Liquid templates from disk

  Useful in development mode. For production, it is probably better to use
  `Miniweb.Template.MemoryStore`.

  Options:

  * `otp_app`: the app serving the templates from its `priv/templates` directory
  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote do
      @behaviour Miniweb.Template.Store

      @dir unquote(otp_app) |> :code.priv_dir() |> Path.join("templates")

      alias Miniweb.Template

      @template_extension ".html"

      @impl true
      def render_named!(name, data, opts) do
        @dir
        |> Path.join(name <> @template_extension)
        |> File.read!()
        |> Template.render!(data, opts)
      end
    end
  end
end
