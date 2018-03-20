defmodule PlugMicropub.HandlerBehaviour do
  @moduledoc """
  Behaviour defining the interface for a PlugMicropub Handler
  """

  @type access_token :: String.t()
  @type handler_error_atom :: :invalid_request | :forbidden | :insufficient_scope
  @type handler_error ::
          {:error, handler_error_atom} | {:error, handler_error_atom, description :: String.t()}

  @callback handle_create(type :: String.t(), properties :: map, access_token) ::
              {:ok, :created | :accepted, url :: String.t()}
              | handler_error

  @callback handle_update(
              url :: String.t(),
              replace :: map,
              add :: map,
              delete :: map,
              access_token
            ) ::
              :ok
              | {:ok, url :: String.t()}
              | handler_error

  @callback handle_delete(url :: String.t(), access_token) ::
              :ok
              | handler_error

  @callback handle_undelete(url :: String.t(), access_token) ::
              :ok
              | {:ok, url :: String.t()}
              | {:error, handler_error}
              | {:error, handler_error, error_description :: String.t()}

  @callback handle_config_query(access_token) ::
              {:ok, map}
              | handler_error

  @callback handle_config_query(access_token) ::
              {:ok, map}
              | handler_error

  @callback handle_source_query(
              url :: String.t(),
              properties :: [String.t()],
              access_token
            ) ::
              {:ok, map}
              | handler_error

  @callback handle_media(file :: Plug.Upload.t(), access_token) ::
              {:ok, url :: String.t()} | handler_error
end
