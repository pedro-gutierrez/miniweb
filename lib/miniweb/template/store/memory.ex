defmodule Miniweb.Template.Store.Memory do
  @moduledoc """
  A builder that gives you a store that caches Liquid templates into memory.

  Useful for production. During development, it is probably better to use
  `Miniweb.Template.DiskStore`.

  Options:

  * `otp_app`: the app serving the templates from its `priv/templates` directory
  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote do
      @behaviour Miniweb.Template.Store

      alias Miniweb.Template

      @templates unquote(templates(otp_app))
      @parsed_templates (for {name, path} <- @templates, into: %{} do
                           {name, path |> File.read!() |> Template.parse!()}
                         end)
      @template_names @parsed_templates |> Map.keys() |> Enum.sort()

      @impl true
      def render_named!(name, data, opts) do
        case Map.get(@parsed_templates, name) do
          nil ->
            raise "No such template #{inspect(name)} in #{inspect(@template_names)}"

          template ->
            Template.render!(template, data, opts)
        end
      end
    end
  end

  @template_extension ".html"

  def templates(otp_app) do
    dir = otp_app |> :code.priv_dir() |> Path.join("templates")

    for path <- Path.wildcard(dir <> "/**/*" <> @template_extension) do
      name = path |> String.replace(dir <> "/", "") |> String.replace(@template_extension, "")

      {name, path}
    end
  end
end
