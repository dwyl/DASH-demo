defmodule MyWebRouter do
  @moduledoc false
  
  use Plug.Router

  @session_options [
    store: :cookie,
    key: "_my_key",
    signing_salt: "my_salt",
    table: :session,
    secret_key_base: String.duplicate("a", 64)
  ]

  plug(Plug.Session, @session_options)
  plug(:fetch_session)
  plug(Plug.CSRFProtection)
  plug(:match)
  plug(:dispatch)

  get "/" do
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.put_session(:csrf_token, token)
    |> HomeController.serve_homepage(%{csrf_token: token})
  end

  get "/js/main.js" do
    HomeController.serve_js(conn, [])
  end

  get "/socket" do
    conn
    |> validate_csrf_token()
    # |> get_user_agent()
    |> WebSockAdapter.upgrade(WebSocketHandler, [], timeout: 60_000)
  
    |> halt()
  end

  get "/dash/:file" do
    %{"file" => file} = conn.params
    dash_path = "priv/dash"
    if File.exists?(Path.join(dash_path, file)) do
      serve_dash_file(conn, dash_path, file)
    else
      send_resp(conn, 404, "not found")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  def serve_dash_file(conn, dash_path, file) do
    case Path.extname(file) do
      ".mpd" ->
        conn
        |> put_resp_content_type("application/dash+xml")
        |> send_file(200, Path.join(dash_path, "manifest.mpd"))
      ".webm" ->
        conn
        |> put_resp_content_type("video/webm")
        |> send_file(200, Path.join(dash_path, file))
      ".m4s" ->
        conn
        |> put_resp_content_type("video/mp4")
        |> send_file(200, Path.join(dash_path, file))
      _ ->
        conn
        |> send_resp(415, "Unsupported media type")
    end
  end

  defp validate_csrf_token(conn) do
    %{"_csrf_token" => session_token} =
      conn
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.get_session()

    %Plug.Conn{query_params: %{"csrf_token" => params_token}} =
      Plug.Conn.fetch_query_params(conn)

    if params_token == session_token do
      conn
    else
      Plug.Conn.halt(conn)
    end
  end
end
