defmodule Miniweb.Routes do
  @moduledoc """
  Generates http routes out of handlers
  """

  @supported_path_params ["id", "name"]

  @doc """
  Return all routes supported by a handler.

  Routes are returned in the form:

    `{method, path, handler_module}`

  and they are inferred from the the handler module name, the functions implemented by the module,
  and the given context.
  """
  def draw(handler, context: context) do
    Code.ensure_compiled!(handler)

    # Remove the context from the handler module
    path = Module.split(handler) -- Module.split(context)

    # Normalise the route path, by identifying path params
    # and separating words with dashes
    path =
      for fragment <- path do
        fragment = Macro.underscore(fragment)

        fragment =
          if Enum.member?(@supported_path_params, fragment) do
            ":" <> fragment
          else
            fragment
          end

        String.replace(fragment, "_", "-")
      end

    # Handle the special case of the root path
    # We model it after the `Root` module at the beginning of the context
    path =
      case "/" <> Enum.join(path, "/") do
        "/root" <> rest -> "/" <> rest
        path -> path
      end

    # Build routes only for the methods that are implemented by the handler
    [:get, :post, :put, :patch, :delete, :options]
    |> Enum.filter(&function_exported?(handler, &1, 2))
    |> Enum.map(fn method -> {method, path, handler} end)
  end
end
