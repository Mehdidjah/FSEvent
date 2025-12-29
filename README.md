# FileSystem

A modern Elixir file system change watcher with advanced features including filtering, throttling, deduplication, debouncing, batching, and telemetry support.

Created by mehdi.

## Features

- **Multi-platform support**: macOS, Linux, FreeBSD, Windows
- **Advanced filtering**: Filter events by extensions, patterns, regex, or custom functions
- **Rate limiting**: Built-in throttling to prevent event flooding
- **Event deduplication**: Automatically removes duplicate events
- **Debouncing**: Delay event processing until activity stops
- **Event batching**: Group multiple events together for efficient processing
- **Async processing**: Process events asynchronously for better performance
- **Health monitoring**: Health check and statistics APIs
- **Telemetry**: Built-in telemetry events for monitoring
- **Configuration validation**: Automatic validation of configuration options
- **Multiple backends**: Native backends for each platform plus polling fallback

## Installation

Add `file_system` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:file_system, "~> 2.0"}
  ]
end
```

**Note**: Version 2.0 requires Elixir ~> 1.14

## Usage

### Basic Usage

```elixir
{:ok, pid} = FileSystem.start_link(dirs: ["/path/to/watch"])
FileSystem.subscribe(pid)

receive do
  {:file_event, _pid, {path, events}} ->
    IO.puts("File changed: #{path}, events: #{inspect(events)}")
  {:file_event, _pid, :stop} ->
    IO.puts("File system watcher stopped")
end
```

### Filtering Events

Filter by file extensions:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/project"],
  extensions: [".ex", ".exs"]
)
```

Filter by glob patterns:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/project"],
  patterns: ["lib/**/*.ex", "test/**/*.exs"],
  exclude_patterns: ["**/test/**"]
)
```

Filter by regular expression:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/project"],
  regex: ~r/\.(ex|exs)$/,
  exclude_regex: ~r/\.git/
)
```

Custom filter function:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/project"],
  filter_fn: fn path ->
    String.contains?(path, "important") and not String.contains?(path, "temp")
  end
)
```

### Throttling

Control the rate of events:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  max_events: 50,
  window_ms: 500
)
```

Disable throttling:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  throttle: false
)
```

### Event Deduplication

Prevent duplicate events:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  deduplicate: true  # default: true
)
```

### Debouncing

Delay event processing until activity stops:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  debounce_ms: 1000  # Wait 1 second after last event
)
```

### Event Batching

Group multiple events together:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  batch_size: 10,           # Batch up to 10 events
  batch_timeout_ms: 500      # Or flush after 500ms
)
```

### Async Processing

Process events asynchronously:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  async: true
)
```

### Health and Statistics

Check worker health:

```elixir
case FileSystem.health(pid) do
  :healthy -> IO.puts("Worker is healthy")
  :unhealthy -> IO.puts("Worker is unhealthy")
end
```

Get statistics:

```elixir
stats = FileSystem.stats(pid)
# %{
#   events_received: 1000,
#   events_filtered: 50,
#   events_throttled: 10,
#   events_duplicate: 5,
#   events_sent: 935,
#   batches_sent: 10,
#   uptime_seconds: 3600
# }
```

Get configuration:

```elixir
config = FileSystem.config(pid)
# Returns the current configuration map
```

### Telemetry

The library emits telemetry events that you can subscribe to:

```elixir
:telemetry.attach(
  "file-system-handler",
  [:file_system, :event_received],
  fn _event_name, measurements, metadata, _config ->
    IO.inspect({measurements, metadata})
  end,
  nil
)
```

Available events:

- `[:file_system, :worker_started]` - Worker started
- `[:file_system, :worker_start_failed]` - Worker failed to start
- `[:file_system, :backend_exited]` - Backend process exited
- `[:file_system, :event_received]` - Event received from backend
- `[:file_system, :event_filtered]` - Event filtered out
- `[:file_system, :event_throttled]` - Event rate limited
- `[:file_system, :event_duplicate]` - Duplicate event detected
- `[:file_system, :event_sent]` - Event sent to subscribers
- `[:file_system, :batch_sent]` - Batch of events sent
- `[:file_system, :subscriber_added]` - New subscriber added
- `[:file_system, :subscriber_removed]` - Subscriber removed

### Backend Options

#### macOS (FSMac)

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  backend: :fs_mac,
  latency: 0.5,
  no_defer: false,
  watch_root: true
)
```

#### Linux/FreeBSD (FSInotify)

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  backend: :fs_inotify,
  recursive: true
)
```

#### Windows (FSWindows)

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  backend: :fs_windows,
  recursive: true
)
```

#### Polling (FSPoll)

Works on all platforms but less efficient:

```elixir
FileSystem.start_link(
  dirs: ["/path/to/watch"],
  backend: :fs_poll,
  interval: 1000
)
```

## Configuration

You can configure backends in `config.exs`:

```elixir
config :file_system, :fs_inotify,
  executable_file: "/usr/local/bin/inotifywait"

config :file_system, :fs_mac,
  executable_file: "/path/to/mac_listener"
```

## License

Apache 2.0

## Author

Created and developed by mehdi. All code, documentation, and features are original work.
