# Usage:
#   elixir scripts/manifest_search.exs <keyword> [manifest_path]
#
# Searches the compile manifest for modules matching a keyword.
# Results are grouped by top-level namespace with module counts.
#
# Examples:
#   elixir scripts/manifest_search.exs account
#   elixir scripts/manifest_search.exs payroll
#   elixir scripts/manifest_search.exs shift

defmodule ManifestSearch do
  def run(args) do
    {keyword, manifest_path} = parse_args(args)
    keyword_down = String.downcase(keyword)

    data = File.read!(manifest_path)
    term = :erlang.binary_to_term(data)
    modules_map = elem(term, 1)

    matching_modules =
      modules_map
      |> Enum.filter(fn {mod, {:module, _, _, _, external?, _}} ->
        not external? and String.contains?(String.downcase(Atom.to_string(mod)), keyword_down)
      end)
      |> Enum.map(fn {mod, {:module, _, files, _, _, _}} ->
        name = mod |> Atom.to_string() |> String.replace_leading("Elixir.", "")
        file = List.first(files)
        {name, file}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    IO.puts("## Search results for \"#{keyword}\" (#{length(matching_modules)} modules)\n")

    # Group by top-level namespace (first two segments, e.g. Backend.Accounts)
    grouped =
      matching_modules
      |> Enum.group_by(fn {name, _} ->
        parts = String.split(name, ".")
        Enum.take(parts, 2) |> Enum.join(".")
      end)
      |> Enum.sort_by(fn {ns, _} -> ns end)

    for {namespace, modules} <- grouped do
      IO.puts("### #{namespace} (#{length(modules)} modules)\n")

      for {name, file} <- modules do
        # Show just the part after the namespace prefix for readability
        short =
          case String.trim_leading(name, namespace <> ".") do
            ^name -> name
            trimmed -> trimmed
          end

        IO.puts("  - #{short}  (#{file})")
      end

      IO.puts("")
    end
  end

  defp parse_args([keyword]) do
    {keyword, find_manifest()}
  end

  defp parse_args([keyword, manifest]) do
    {keyword, manifest}
  end

  defp parse_args(_) do
    IO.puts("Usage: elixir manifest_search.exs <keyword> [manifest_path]")
    System.halt(1)
  end

  defp find_manifest do
    case detect_app_name() do
      {:ok, app} ->
        path = "_build/dev/lib/#{app}/.mix/compile.elixir"
        if File.exists?(path), do: path, else: manifest_not_found()
      :error ->
        manifest_not_found()
    end
  end

  defp detect_app_name do
    if File.exists?("mix.exs") do
      case Regex.run(~r/app:\s*:(\w+)/, File.read!("mix.exs")) do
        [_, app] -> {:ok, app}
        _ -> :error
      end
    else
      :error
    end
  end

  defp manifest_not_found do
    IO.puts("ERROR: Could not find compile manifest. Pass the path as an argument.")
    System.halt(1)
  end
end

ManifestSearch.run(System.argv())
