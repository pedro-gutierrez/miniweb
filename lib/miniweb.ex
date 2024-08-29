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
        foo: "bar",
      ],
      extra: [
        base_url: "...",
        ...
      ]
  ```
  """

  alias Miniweb.Routes
  require Logger

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    log = Keyword.get(opts, :log, false)
    cookies = Keyword.get(opts, :cookies)
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

    # Setup the initial state
    initial_state = keyword_to_map(state)
    Logger.debug("Miniweb initial state: " <> inspect(initial_state, pretty: true))

    # Generate a router matcher for each route
    matchers =
      for {method, path, handler} <- routes do
        quote do
          unquote(method)(unquote(path),
            do: handle_request(unquote(conn), unquote(method), unquote(handler), @initial_state)
          )
        end
      end

    quote location: :keep do
      use Plug.Router
      use Plug.ErrorHandler
      use Miniweb.View, otp_app: unquote(otp_app)

      import Miniweb, only: [setting: 1]
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
          value = @cookies |> Keyword.fetch!(:secret_key_base) |> setting()

          put_in(conn.secret_key_base, value)
        end

        plug(:put_secret_key_base)

        plug(Plug.Session,
          store: :cookie,
          key: "_miniweb",
          signing_salt: @cookies |> Keyword.fetch!(:signing_salt) |> setting(),
          encryption_salt: @cookies |> Keyword.fetch!(:encryption_salt) |> setting(),
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

      @initial_state unquote(Macro.escape(initial_state))

      # Application routes from handlers
      unquote_splicing(matchers)

      # Catch all route, that renders a styled not found page using a simple layout
      match _ do
        opts = [
          status: 404,
          view: :error_layout,
          data: %{
            title: "Not found",
            kind: "",
            reason: "No such route",
            stack: ""
          }
        ]

        do_response({:render, opts}, unquote(conn))
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

        data =
          conn
          |> read_session()
          |> Map.merge(data)

        Logger.error(inspect(data))

        opts = [
          data: data,
          status: conn.status,
          view: :error_layout
        ]

        do_response({:render, opts}, conn)
      end

      # Handle a request.
      # We initialise the session, call the handler, and handle the response
      defp handle_request(conn, method, handler, initial_state) do
        conn =
          conn
          |> debug_params()
          |> init_session(method, initial_state)

        session = read_session(conn)

        handler
        |> apply(method, [conn.params, session])
        |> do_response(conn)
      end

      # Helper functions to either building html markup
      # or sending a redirect back to the browser
      defp do_response({:render, opts}, conn) do
        view = Keyword.fetch!(opts, :view)
        data = Keyword.get(opts, :data, [])
        session = Keyword.get(opts, :session, %{})

        conn = save_session(conn, session)

        data =
          conn
          |> read_session()
          |> Map.merge(data)

        Logger.debug(
          "Miniweb rendering view #{inspect(view)} with data: " <> inspect(data, pretty: true)
        )

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
        base_url = get_session(conn, "base_url") || ""
        url = base_url <> url

        conn
        |> put_resp_content_type("text/text")
        |> put_resp_header("Location", url)
        |> save_session(session)
        |> send_resp(status, "")
      end

      # Restore the session if necessary
      # By convention this only applies to certains routes (eg GET requests).
      # This is to ensure we work with default values in scenarios where a bookmarked url is being
      # accessed while at the same time the cookies were cleared on the browser side
      defp init_session(conn, :get, initial_state) do
        Enum.reduce(initial_state, conn, fn {key, default}, conn ->
          case get_session(conn, key) do
            nil -> put_session(conn, key, default)
            _ -> conn
          end
        end)
      end

      defp init_session(conn, _, _), do: conn

      # Reads the entire session in order to include it in the assigns so that the state is made
      # available to views. Keys are given as atoms.
      def read_session(conn) do
        for {key, _} <- @initial_state, into: %{} do
          {key, get_session(conn, to_string(key))}
        end
      end

      # Save the session by merging the given map into the existing session
      defp save_session(conn, session) do
        conn =
          Enum.reduce(session, conn, fn {key, value}, conn ->
            put_session(conn, key, value)
          end)

        Logger.debug("Miniweb session: " <> (conn |> get_session() |> inspect(pretty: true)))

        conn
      end

      defp debug_params(conn) do
        Logger.debug("Miniweb params: " <> inspect(conn.params, pretty: true))

        conn
      end
    end
  end

  defp extract_alias({:__aliases__, _, parts}), do: Module.concat(parts)
  defp extract_alias(module) when is_atom(module), do: module

  def setting({m, f, a}), do: apply(m, f, a)
  def setting(other), do: other

  defp keyword_to_map(list) when is_list(list) do
    if Keyword.keyword?(list) do
      for {key, value} <- list, into: %{} do
        {key, keyword_to_map(value)}
      end
    else
      Enum.map(list, &keyword_to_map/1)
    end
  end

  defp keyword_to_map(other), do: other
end
