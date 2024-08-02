defmodule Miniweb.Template do
  @moduledoc """
  Support for liquid templates
  """

  @doc """
  Render a template given its source, using the given data as assigns

  Options:

  * `:templates_store`: a module indicating how to retrieve and render templates
  """
  def render!(source, data, opts) when is_binary(source) do
    source
    |> parse!()
    |> render!(data, opts)
  end

  def render!(template, data, opts) do
    template
    |> Solid.render!(data, opts)
    |> to_string()
  end

  @doc """
  Parse a template
  """
  def parse!(source) when is_binary(source) do
    Solid.parse!(source, parser: Miniweb.Template.Parser)
  end

  @doc """
  Reads a template by name.

  Options:

  * `:templates`: a module indicating how to retrieve and render templates
  """
  def render_named!(name, data, opts) do
    store = Keyword.fetch!(opts, :templates)

    store.render_named!(name, data, opts)
  end
end
