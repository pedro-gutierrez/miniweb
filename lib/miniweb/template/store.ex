defmodule Miniweb.Template.Store do
  @moduledoc """
  A behaviour to fetch and render templates
  """

  @doc """
  Render a template givens its name.

  A map of assigns can be passed.
  """
  @callback render_named!(name :: String.t(), data :: map(), opts :: keyword()) :: String.t()
end
