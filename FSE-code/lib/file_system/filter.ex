defmodule FileSystem.Filter do
  @moduledoc """
  File path filtering utilities for file system events.

  This module provides flexible filtering capabilities to control which file system
  events are processed. Multiple filter types can be combined, and all must pass
  for an event to be included.

  ## Filter Types

  - **Extensions**: Match files by their extension (e.g., `.ex`, `.exs`)
  - **Glob Patterns**: Match using glob patterns (e.g., `lib/**/*.ex`)
  - **Exclude Patterns**: Exclude paths matching specific patterns
  - **Regular Expressions**: Match using regex patterns
  - **Exclude Regex**: Exclude paths matching regex patterns
  - **Custom Functions**: Use custom logic for advanced filtering

  ## Filter Order

  Filters are applied in the following order:
  1. Extensions check
  2. Include patterns check
  3. Exclude patterns check
  4. Include regex check
  5. Exclude regex check
  6. Custom filter function

  All checks must pass for the path to be included.

  Created by mehdi.
  """

  @doc """
  Checks if a file path matches the given filters.

  ## Options
  - `:extensions` - List of file extensions to include (e.g., [".ex", ".exs"])
  - `:patterns` - List of glob patterns to match (e.g., ["**/*.ex", "lib/**"])
  - `:exclude_patterns` - List of glob patterns to exclude
  - `:regex` - Regular expression to match against the full path
  - `:exclude_regex` - Regular expression to exclude paths
  - `:filter_fn` - Custom function `(path -> boolean)` for advanced filtering

  Returns `true` if the path should be included, `false` otherwise.
  """
  @spec matches?(String.t(), Keyword.t()) :: boolean()
  def matches?(path, opts \\ []) do
    cond do
      not matches_extensions?(path, Keyword.get(opts, :extensions)) -> false
      not matches_patterns?(path, Keyword.get(opts, :patterns)) -> false
      matches_exclude_patterns?(path, Keyword.get(opts, :exclude_patterns)) -> false
      not matches_regex?(path, Keyword.get(opts, :regex)) -> false
      matches_exclude_regex?(path, Keyword.get(opts, :exclude_regex)) -> false
      not matches_filter_fn?(path, Keyword.get(opts, :filter_fn)) -> false
      true -> true
    end
  end

  defp matches_extensions?(_path, nil), do: true
  defp matches_extensions?(_path, []), do: true

  defp matches_extensions?(path, extensions) when is_list(extensions) do
    path_ext = Path.extname(path) |> String.downcase()
    extensions = Enum.map(extensions, &String.downcase/1)
    path_ext in extensions
  end

  defp matches_patterns?(_path, nil), do: true
  defp matches_patterns?(_path, []), do: true

  defp matches_patterns?(path, patterns) when is_list(patterns) do
    normalized_path = Path.expand(path) |> Path.absname()

    Enum.any?(patterns, fn pattern ->
      matches_glob_pattern?(normalized_path, pattern)
    end)
  end

  defp matches_glob_pattern?(path, pattern) do
    try do
      normalized_pattern = normalize_glob_pattern(pattern)
      Regex.match?(normalized_pattern, path)
    rescue
      _ -> false
    end
  end

  defp normalize_glob_pattern(pattern) do
    pattern
    |> String.replace(~r/\*\*/, ".*")
    |> String.replace(~r/\*/, "[^/]*")
    |> String.replace(~r/\?/, ".")
    |> Regex.compile!()
  end

  defp matches_exclude_patterns?(_path, nil), do: false
  defp matches_exclude_patterns?(_path, []), do: false

  defp matches_exclude_patterns?(path, patterns) when is_list(patterns) do
    Enum.any?(patterns, fn pattern ->
      case Path.wildcard(pattern) do
        [] -> false
        matches -> path in matches
      end
    end)
  end

  defp matches_regex?(_path, nil), do: true
  defp matches_regex?(_path, ""), do: true

  defp matches_regex?(path, regex) when is_binary(regex) do
    case Regex.compile(regex) do
      {:ok, compiled} -> Regex.match?(compiled, path)
      {:error, _} -> true
    end
  end

  defp matches_regex?(path, %Regex{} = regex), do: Regex.match?(regex, path)

  defp matches_exclude_regex?(_path, nil), do: false
  defp matches_exclude_regex?(_path, ""), do: false

  defp matches_exclude_regex?(path, regex) when is_binary(regex) do
    case Regex.compile(regex) do
      {:ok, compiled} -> Regex.match?(compiled, path)
      {:error, _} -> false
    end
  end

  defp matches_exclude_regex?(path, %Regex{} = regex), do: Regex.match?(regex, path)

  defp matches_filter_fn?(_path, nil), do: true
  defp matches_filter_fn?(path, filter_fn) when is_function(filter_fn, 1), do: filter_fn.(path)
  defp matches_filter_fn?(_path, _), do: true
end
