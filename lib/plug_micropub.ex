defmodule PlugMicropub do
  @moduledoc """
  A Plug for building a Micropub server.

  To use:

  """
  use Plug.Router

  plug :match
  plug :dispatch

  # Plug Callbacks

  @doc false
  def init(opts) do
    handler =
      Keyword.get(opts, :handler) || raise ArgumentError, "Micropub Plug requires :handler option"

    json_encoder =
      Keyword.get(opts, :json_encoder) ||
        raise ArgumentError, "Micropub Plug requires :json_encoder option"

    [handler: handler, json_encoder: json_encoder]
  end

  @doc false
  def call(conn, opts) do
    conn = put_private(conn, :plug_micropub, opts)
    super(conn, opts)
  end

  # Routes

  post "/" do
    with {:ok, access_token, conn} <- get_access_token(conn),
         {:ok, action, conn} <- get_action(conn) do
      handle_action(action, access_token, conn)
    else
      error -> send_error(conn, error)
    end
  end

  get "/" do
    with {:ok, access_token, conn} <- get_access_token(conn),
         {:ok, query} <- get_query(conn) do
      handle_query(query, access_token, conn)
    else
      error -> send_error(conn, error)
    end
  end

  post "/media" do
    handler = conn.private[:plug_micropub][:handler]

    with {:ok, access_token, conn} <- get_access_token(conn),
         {:ok, file} <- get_file(conn),
         {:ok, url} <- handler.handle_media(file, access_token) do
      conn
      |> put_resp_header("location", url)
      |> send_resp(:created, "")
    else
      error -> send_error(conn, error)
    end
  end

  match _ do
    send_error(conn, {:error, :invalid_request})
  end

  # Internal Functions

  defp send_content(conn, content) do
    json_encoder = conn.private[:plug_micropub][:json_encoder]
    body = json_encoder.encode!(content)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:ok, body)
  end

  defp send_error(conn, {:error, error}) do
    body = %{error: error}
    _send_error(conn, body)
  end

  defp send_error(conn, {:error, error, description}) do
    body = %{error: error, error_description: description}
    _send_error(conn, body)
  end

  defp _send_error(conn, body) do
    json_encoder = conn.private[:plug_micropub][:json_encoder]

    code = get_error_code(body.error)
    body = json_encoder.encode!(body)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, body)
  end

  defp get_error_code(:insufficient_scope), do: :unauthorized
  defp get_error_code(:invalid_request), do: :bad_request
  defp get_error_code(code), do: code

  defp get_action(conn) do
    {action, body_params} = Map.pop(conn.body_params, "action")
    conn = %Plug.Conn{conn | body_params: body_params}

    case action do
      nil ->
        {:ok, :create, conn}

      action when action in ["delete", "undelete", "update"] ->
        {:ok, String.to_existing_atom(action), conn}

      _ ->
        {:error, :invalid_request}
    end
  end

  defp get_query(conn) do
    case Map.fetch(conn.query_params, "q") do
      {:ok, query} when query in ["config", "source", "syndicate-to"] ->
        {:ok, String.to_existing_atom(query)}

      _ ->
        {:error, :invalid_request}
    end
  end

  defp get_file(conn) do
    case Map.fetch(conn.body_params, "file") do
      {:ok, file} -> {:ok, file}
      :error -> {:error, :invalid_request}
    end
  end

  defp get_access_token(conn) do
    {access_token, body_params} = Map.pop(conn.body_params, "access_token")
    conn = %Plug.Conn{conn | body_params: body_params}

    case access_token do
      nil -> parse_auth_header(conn)
      access_token -> {:ok, access_token, conn}
    end
  end

  defp parse_auth_header(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         _ = IO.inspect(header),
         "Bearer" <> token <- header,
         do: {:ok, String.trim(token), conn},
         else: (_ -> {:error, :unauthorized})
  end

  defp handle_action(:create, access_token, conn) do
    content_type = conn |> get_req_header("content-type") |> List.first()
    handler = conn.private[:plug_micropub][:handler]

    with {:ok, type, properties} <- parse_create_body(content_type, conn.body_params),
         {:ok, code, url} <- handler.handle_create(type, properties, access_token) do
      conn
      |> put_resp_header("location", url)
      |> send_resp(code, "")
    else
      error -> send_error(conn, error)
    end
  end

  defp handle_action(:update, access_token, conn) do
    content_type = conn |> get_req_header("content-type") |> List.first()

    with "application/json" <- content_type,
         {url, properties} when is_binary(url) <- Map.pop(conn.body_params, "url"),
         {:ok, replace, add, delete} <- parse_update_properties(properties),
         do: do_update(conn, access_token, url, replace, add, delete),
         else: (_ -> send_error(conn, {:error, :invalid_request}))
  end

  defp handle_action(:delete, access_token, conn) do
    with {:ok, url} <- Map.fetch(conn.body_params, "url"),
         do: do_delete(conn, access_token, url),
         else: (_ -> send_error(conn, {:error, :invalid_request}))
  end

  defp handle_action(:undelete, access_token, conn) do
    with {:ok, url} <- Map.fetch(conn.body_params, "url"),
         do: do_undelete(conn, access_token, url),
         else: (_ -> send_error(conn, {:error, :invalid_request}))
  end

  defp handle_query(:config, access_token, conn) do
    handler = conn.private[:plug_micropub][:handler]

    case handler.handle_config_query(access_token) do
      {:ok, content} -> send_content(conn, content)
      error -> send_error(conn, error)
    end
  end

  defp handle_query(:source, access_token, conn) do
    with {:ok, url} <- Map.fetch(conn.query_params, "url"),
         do: do_source_query(conn, access_token, url),
         else: (_ -> send_error(conn, {:error, :invalid_request}))
  end

  defp handle_query(:"syndicate-to", access_token, conn) do
    handler = conn.private[:plug_micropub][:handler]

    case handler.handle_syndicate_to_query(access_token) do
      {:ok, content} -> send_content(conn, content)
      error -> send_error(conn, error)
    end
  end

  defp parse_update_properties(properties) do
    properties = Map.take(properties, ["replace", "add", "delete"])

    valid? =
      Enum.all?(properties, fn
        {"delete", prop} when is_list(prop) ->
          Enum.all?(prop, &is_binary/1)

        {_k, prop} when is_map(prop) ->
          Enum.all?(prop, fn
            {_k, v} when is_list(v) -> true
            _ -> false
          end)

        _ ->
          false
      end)

    if valid? do
      replace = Map.get(properties, "replace", %{})
      add = Map.get(properties, "add", %{})
      delete = Map.get(properties, "delete", %{})
      {:ok, replace, add, delete}
    else
      :error
    end
  end

  defp do_update(conn, access_token, url, replace, add, delete) do
    handler = conn.private[:plug_micropub][:handler]

    case handler.handle_update(url, replace, add, delete, access_token) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:ok, url} ->
        conn
        |> put_resp_header("location", url)
        |> send_resp(:created, "")

      error ->
        send_error(conn, error)
    end
  end

  defp do_delete(conn, access_token, url) do
    handler = conn.private[:plug_micropub][:handler]

    case handler.handle_delete(url, access_token) do
      :ok -> send_resp(conn, :no_content, "")
      error -> send_error(conn, error)
    end
  end

  defp do_undelete(conn, access_token, url) do
    handler = conn.private[:plug_micropub][:handler]

    case handler.handle_undelete(url, access_token) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:ok, url} ->
        conn
        |> put_resp_header("location", url)
        |> send_resp(:created, "")

      error ->
        send_error(conn, error)
    end
  end

  defp do_source_query(conn, access_token, url) do
    handler = conn.private[:plug_micropub][:handler]
    properties = Map.get(conn.query_params, "properties", [])

    case handler.handle_source_query(url, properties, access_token) do
      {:ok, content} -> send_content(conn, content)
      error -> send_error(conn, error)
    end
  end

  defp parse_create_body("application/json", params) do
    with {:ok, ["h-" <> type]} <- Map.fetch(params, "type"),
         {:ok, properties} when is_map(properties) <- Map.fetch(params, "properties") do
      properties =
        properties
        |> Enum.reject(&match?({"mp-" <> _, _}, &1))
        |> Map.new()

      {:ok, type, properties}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp parse_create_body(_, params) do
    with {type, params} when is_binary(type) <- Map.pop(params, "h") do
      properties =
        params
        |> Enum.reject(&match?({"mp-" <> _, _}, &1))
        |> Enum.map(fn {k, v} -> {k, List.wrap(v)} end)
        |> Map.new()

      {:ok, type, properties}
    else
      _ -> {:error, :invalid_request}
    end
  end
end
