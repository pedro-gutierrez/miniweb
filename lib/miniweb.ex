defmodule Miniweb do
  @moduledoc """
  A small and opinionated web framework.

  Usage:

  ```elixir
  defmodule MyApp.Web,
    use Miniweb,
      otp_app: :my_app,
      cookies: [
        secret_key_base: "...",
        signing_salt: "...",
        encryption_salt: "...",
      ],
      log: true,
      handlers: [
        MyApp.Handlers.Root,
        MyApp.Handlers.Posts,
        MyApp.Handlers.Posts.Id,
        MyApp.Handlers.Comments
      ],
      state: [
        :foo,
        :bar,
        ...
      ],
      extra: [
        base_url: "...",
        ...
      ]
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
  require Logger

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    log = Keyword.get(opts, :log, false)
    cookies = Keyword.get(opts, :cookies)
    extra = Keyword.fetch!(opts, :extra)
    state = Keyword.fetch!(opts, :state)

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

    Logger.debug("Miniweb routes: " <> inspect(routes, pretty: true))

    # Generate a router matcher for each route
    matchers =
      for {method, path, handler} <- routes do
        quote do
          unquote(method)(unquote(path),
            do:
              unquote(conn)
              |> debug_params()
              |> unquote(handler).unquote(method)(unquote(conn).params)
              |> do_response(unquote(conn))
          )
        end
      end

    quote location: :keep do
      use Plug.Router
      use Plug.ErrorHandler
      use Miniweb.View, otp_app: unquote(otp_app)

      import Miniweb, only: [setting_value: 1]
      require Logger

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

      plug(Plug.Parsers,
        parsers: [:urlencoded, :multipart],
        pass: ["*/*"]
      )

      plug(Plug.CSRFProtection)
      plug(Plug.RequestId)
      plug(Plug.MethodOverride)

      # Serve static assets from the user's app priv directory
      plug(Plug.Static, at: "/static", from: {unquote(otp_app), "priv/static"})

      plug(:match)
      plug(:dispatch)

      # Application routes from handlers
      unquote_splicing(matchers)

      # Catch all route, that renders a styled not found page using a simple layout
      match _ do
        do_response(
          {:render, status: 404, template: "404", layout: "layouts/simple"},
          unquote(conn)
        )
      end

      @impl Plug.ErrorHandler
      def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
        kind = inspect(kind)
        reason = inspect(reason)
        stack = Exception.format_stacktrace(stack)

        data = %{
          title: Plug.Conn.Status.reason_atom(conn.status),
          kind: kind,
          reason: reason,
          stack: stack
        }

        Logger.error(inspect(data))

        opts = [
          data: data,
          status: conn.status,
          view: :error_layout
        ]

        do_response({:render, opts}, conn)
      end

      @state unquote(state)

      # Helper functions to either building html markup
      # or sending a redirect back to the browser
      defp do_response({:render, opts}, conn) do
        view = Keyword.fetch!(opts, :view)
        data = Keyword.get(opts, :data, [])
        session = Keyword.get(opts, :session, %{})

        conn = put_session(conn, session)

        session = for key <- @state, into: %{} do
          {key, get_session(conn, key)}
        end

        data =
          extra()
          |> Map.new()
          |> Map.merge(session)
          |> Map.merge(data)

        Logger.debug("Miniweb data: " <> inspect(data, pretty: true))

        html = render(view, data)

        status = Keyword.get(opts, :status, 200)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(status, html)
      end

      defp do_response({:redirect, opts}, conn) do
        url = Keyword.get(opts, :url, "/")
        status = Keyword.get(opts, :status, 302)
        session = Keyword.get(opts, :session, %{})
        base_url = extra() |> Keyword.fetch!(:base_url)
        url = base_url <> url

        conn
        |> put_resp_content_type("text/text")
        |> put_resp_header("Location", url)
        |> put_session(session)
        |> send_resp(status, "")
      end

      defp put_session(conn, session) do
        conn = Enum.reduce(session, conn, fn {key, value}, conn ->
          put_session(conn, key, value)
        end)

        Logger.debug("Miniweb session: " <> (conn |> get_session() |> inspect(pretty: true)))

        conn
      end

      defp debug_params(conn) do
        Logger.debug("Miniweb params: " <> inspect(conn.params, pretty: true))

        conn
      end

      defp extra, do: setting_value(unquote(extra))
    end
  end

  defp extract_alias({:__aliases__, _, parts}), do: Module.concat(parts)
  defp extract_alias(module) when is_atom(module), do: module

  def setting_value({m, f, a}), do: apply(m, f, a)
  def setting_value(other), do: other
end
