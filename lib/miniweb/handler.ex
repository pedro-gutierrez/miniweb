defmodule Miniweb.Handler do
  @moduledoc """
  A Miniweb handler is in charge of defining routes and handling them.

  Routes are inferred from the module names themselves.

  Usage:

  ```elixir
  defmodule MyApp.Handlers.Posts.Id do
    use Miniweb.Handler,
      path_params: [:id]

    # This will handle GET /posts/:id
    # if the context for all handlers is `MyApp.Handlers`
    def get(conn, params, session) do
      data = %{
        "title" => "...",
        "body" => "..."
      }

      {:render, [template: "post", data: data]}
    end
  end
  """

  @type method() :: atom()
  @type path() :: String.t()
  @type route() :: {method(), path(), module()}

  @doc "Returns the routes defined by the handler, in a given context"
  @callback routes(context :: module()) :: list(route())

  defmacro __using__(opts) do
    path_params =
      opts
      |> Keyword.get(:path_params, [])
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.replace(&1, ":", ""))

    quote do
      @behaviour Miniweb.Handler

      @path_params unquote(path_params)

      @impl true
      def routes(context) do
        # Remove the context from the handler module
        path = Module.split(__MODULE__) -- Module.split(context)

        # Normalise the route path, by identifying path params
        # and separating words with dashes
        path =
          for fragment <- path do
            fragment = Macro.underscore(fragment)

            fragment =
              if Enum.member?(@path_params, fragment) do
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
        |> Enum.filter(&function_exported?(__MODULE__, &1, 2))
        |> Enum.map(fn method -> {method, path, __MODULE__} end)
      end
    end
  end
end
