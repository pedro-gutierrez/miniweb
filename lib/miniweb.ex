defmodule Miniweb do
  @moduledoc """
  A small and opinionated web framework.

  Usage:

  ```elixir
  defmodule MyApp.Web,
    use Miniweb,
      otp_app: :my_app,
      base_url: "...",
      cookies: [
        secret_key_base: "...",
        signing_salt: "...",
        encryption_salt: "...",
      ],
      log: true,
      templates: MyApp.Templates,
      handlers: [
        MyApp.Handlers.Root,
        MyApp.Handlers.Posts,
        MyApp.Handlers.Posts.Id,
        MyApp.Handlers.Comments
      ],
      extra: %{ ... }
  ```

  with an in-memory template store:

  ```elixir
  defmodule MyApp.Templates do
    use Miniweb.Template.Store.Memory,
      otp_app: :my_app
  end

  ```
  """

  alias Miniweb.Routes

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    log = Keyword.get(opts, :log, false)
    templates = Keyword.get(opts, :templates, __CALLER__.module)
    cookies = Keyword.get(opts, :cookies)
    base_url = Keyword.get(opts, :base_url, "")
    debug = Keyword.get(opts, :debug, false)
    conn = Macro.var(:conn, nil)

    handlers =
      opts
      |> Keyword.fetch!(:handlers)
      |> Enum.map(&extract_alias/1)

    # Infer the root context for all handler modules
    # By convention, we look for the handler that has the `Root`
    # bit, and we extract everything before that and we consider that's the context
    context =
      handlers
      |> Enum.map(&Module.split/1)
      |> Enum.find(&Enum.member?(&1, "Root"))
      |> then(fn
        nil ->
          raise "No root handler provided"

        handler ->
          index = Enum.find_index(handler, &(&1 == "Root"))
          Enum.slice(handler, 0, index)
      end)
      |> Module.concat()

    # Draw all routes
    routes = Enum.flat_map(handlers, &Routes.draw(&1, context: context))

    pretty_routes =
      for {method, path, _handler} <- routes do
        "#{method |> to_string() |> String.upcase()} #{path}"
      end

    if debug do
      IO.puts("#{inspect(handlers: handlers, routes: routes)}")
    end

    # Generate a router matcher for each route
    matchers =
      for {method, path, handler} <- routes do
        quote do
          unquote(method)(unquote(path),
            do:
              unquote(conn)
              |> unquote(handler).unquote(method)(unquote(conn).params)
              |> do_response(unquote(conn))
          )
        end
      end

    # If we got a static list of extra user data, then convert this into a map where keys are
    # strings so that we can make this available to templates
    extra =
      with pairs when is_list(pairs) <- Keyword.get(opts, :extra, []) do
        for {k, v} <- pairs, into: %{} do
          {to_string(k), v}
        end
      end

    quote do
      use Plug.Router
      import Miniweb, only: [setting_value: 1]

      alias Miniweb.Template

      # For informational and/or debugging purposes only
      def routes, do: unquote(pretty_routes)

      # Optional request logger. If miniweb is being used from within a larger Phoenix
      # application, then this might not be necessary
      @log unquote(log)

      if @log, do: plug(Miniweb.Logger)

      # Configure session management using cookies.
      # This is relevant when Miniweb is used standalone, ie, outside a phoenix application.
      # If using Phoenix, chances are that sessions configuration is already made in the
      # Phoenix endpoint, and in that case, there is no need to do it again here
      @cookies unquote(cookies)

      if is_list(@cookies) do
        def put_secret_key_base(conn, _) do
          value = @cookies |> Keyword.fetch!(:secret_key_base) |> setting_value()

          put_in(conn.secret_key_base, value)
        end

        plug(:put_secret_key_base)

        plug(Plug.Session,
          store: :cookie,
          key: "_miniweb",
          signing_salt: @cookies |> Keyword.fetch!(:signing_salt) |> setting_value(),
          encryption_salt: @cookies |> Keyword.fetch!(:encryption_salt) |> setting_value(),
          http_only: true,
          log: false
        )

        plug(:fetch_session)
      end

      # Serve static assets from the user's app priv directory
      plug(Plug.Static, at: "/static", from: {unquote(otp_app), "priv/static"})

      plug(:match)
      plug(:dispatch)

      # Application routes from handlers
      unquote_splicing(matchers)

      # Catch all route, that renders a styled not found page
      # using a simple layout
      @not_found_opts [
        status: 404,
        template: "not_found",
        layout: "layouts/simple"
      ]

      match _ do
        do_response({:render, @not_found_opts}, unquote(conn))
      end

      # The provider of templates. We need to pass this option to the template
      # rendering api so that referenced templates can be resolved during runtime
      @templates unquote(templates)
      @render_opts [templates: @templates]

      # Helper functions to either building html markup
      # or sending a redirect back to the browser
      defp do_response({:render, opts}, conn) do
        template = Keyword.fetch!(opts, :template)
        layout = opts[:layout] || "layouts/default"

        data = opts[:data] || %{}

        data =
          extra()
          |> Map.put("baseUrl", base_url())
          |> Map.merge(data)
          |> Map.put("main", template)

        html = Template.render_named!(layout, data, @render_opts)

        status = opts[:status] || 200

        conn
        |> put_session(opts)
        |> put_resp_content_type("text/html")
        |> send_resp(status, html)
      end

      defp do_response({:redirect, opts}, conn) do
        url = Keyword.fetch!(opts, :url)
        status = Keyword.get(opts, :status, 303)
        url = base_url() <> url

        conn
        |> put_resp_content_type("text/text")
        |> put_resp_header("Location", url)
        |> put_session(opts)
        |> send_resp(status, "")
      end

      defp put_session(conn, opts) do
        session = opts[:session] || %{}

        Enum.reduce(session, conn, fn {key, value}, acc ->
          put_session(acc, key, value)
        end)
      end

      defp base_url, do: setting_value(unquote(base_url))
      defp extra, do: setting_value(unquote(Macro.escape(extra)))
    end
  end

  defp extract_alias({:__aliases__, _, parts}), do: Module.concat(parts)
  defp extract_alias(module) when is_atom(module), do: module

  def setting_value({m, f, a}), do: apply(m, f, a)
  def setting_value(other), do: other
end
