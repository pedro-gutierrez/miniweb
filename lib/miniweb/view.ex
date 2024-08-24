defmodule Miniweb.View do
  @moduledoc """
  Miniweb views are based on EEx and the Phoenix HTML engine.

  Some extra features are available:

  * composing views via partials
  * csrf token protection
  * live recompilation

  Views are loadeded from the app `priv/views` folder and cached into memory
  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote do
      require EEx
      require Logger

      import Phoenix.HTML
      import Plug.CSRFProtection, only: [get_csrf_token: 0]

      @extension ".eex"
      @dir unquote(otp_app) |> :code.priv_dir() |> Path.join("views")
      @paths Path.wildcard(@dir <> "/**/*" <> @extension)

      # If the template source changes, mark the module for recompilation
      # this is useful during development
      if Mix.env() == :dev do
        for path <- @paths do
          @external_resource path
        end
      end

      defp partial(assigns, name), do: assigns[name] || name

      # Render a nested view, given its name
      # This macro is to be used within a .eex template
      defmacro view(name) do
        assigns = Macro.var(:assigns, nil)

        quote do
          partial = partial(unquote(assigns), unquote(name))

          apply(__MODULE__, partial, [unquote(assigns)])
        end
      end

      # Render a nested view, given it name, with extra variables. This flavour is useful when
      # iterating through items in a list
      # this macro is to be used within a .eex template
      defmacro view(name, extra_vars) do
        assigns = Macro.var(:assigns, nil)

        quote do
          partial = partial(unquote(assigns), unquote(name))
          assigns = Map.merge(unquote(assigns), unquote(extra_vars))

          apply(__MODULE__, partial, [assigns])
        end
      end

      # Render a html hidden input with a new csrf token. To be used within forms.
      defmacro csrf_protection() do
        quote do
          {:safe, "<input type=\"hidden\" name=\"_csrf_token\" value=\"#{get_csrf_token()}\">"}
        end
      end

      # Load all views in the priv/views directory and compile them into EEx
      # We use the Phoenix.HTML.Engine here to make sure the content generated is html safe by
      # default
      for path <- @paths do
        name =
          path
          |> String.replace(@dir <> "/", "")
          |> String.replace(@extension, "")
          |> String.to_atom()

        EEx.function_from_file(:def, name, path, [:assigns], engine: Phoenix.HTML.Engine)
        Logger.debug("Loaded view #{name}")
      end

      # Convenience function that convers the views's output iodata into a string
      def render(name, vars) do
        {micros, result} = :timer.tc(fn ->
          {:safe, data} = apply(__MODULE__, name, [vars])
          to_string(data)
        end)

        Logger.debug("Miniweb rendered view #{inspect(name)} in #{micros /1000}ms")
        result
      end
    end
  end
end
