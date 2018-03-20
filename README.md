# PlugMicropub

A small library for helping build a Plug-based Micropub server.

A basic example server that implements all [Micropub Rocks!][1] validation
tests can be found [here][2].

## Usage

Basic Usage:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Poison

plug PlugMicropub,
  handler: MyApp.MicropubHandler,
  json_decoder: Poison 
```

### Forwarding

If you want `PlugMicropub` to serve only a particular route, configure your router like:

#### Plug.Router

```elixir
forward "/micropub",
  to: PlugMicropub,
  init_opts: [
	handler: MyApp.MicropubHandler,
	json_decoder: Poison
  ]
```

#### Phoenix.Router

```elixir
forward "/micropub",
  PlugMicropub,
  handler: MyApp.MicropubHandler,
  json_decoder: Poison
```

[1]: https://micropub.rocks/
[2]: https://github.com/bismark/micropub-example
