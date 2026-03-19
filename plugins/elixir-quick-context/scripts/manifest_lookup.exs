# Usage:
#   elixir scripts/manifest_lookup.exs <file_path_or_module> [manifest_path]
#
# Examples:
#   elixir scripts/manifest_lookup.exs lib/backend/shifts.ex
#   elixir scripts/manifest_lookup.exs Backend.Shifts
#   elixir scripts/manifest_lookup.exs lib/backend/shifts.ex _build/dev/lib/backend/.mix/compile.elixir
#
# Accepts multiple targets separated by commas:
#   elixir scripts/manifest_lookup.exs lib/backend/shifts.ex,lib/backend/accounts/user.ex

defmodule ManifestLookup do
  def run(args) do
    {targets_raw, manifest_path} = parse_args(args)
    targets = String.split(targets_raw, ",", trim: true) |> Enum.map(&String.trim/1)

    data = File.read!(manifest_path)
    term = :erlang.binary_to_term(data)
    modules_map = elem(term, 1)
    sources_map = elem(term, 2)

    for target <- targets do
      defined_modules = lookup(target, modules_map, sources_map)
      if defined_modules != [] do
        print_reverse_deps(defined_modules, modules_map, sources_map)
      end
    end
  end

  defp parse_args([target]) do
    {target, find_manifest()}
  end

  defp parse_args([target, manifest]) do
    {target, manifest}
  end

  defp parse_args(_) do
    IO.puts("Usage: elixir manifest_lookup.exs <file_path_or_module> [manifest_path]")
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

  defp lookup(target, modules_map, sources_map) do
    cond do
      # Looks like a file path
      String.ends_with?(target, ".ex") or String.ends_with?(target, ".exs") ->
        lookup_by_file(target, modules_map, sources_map)

      # Looks like a module name
      true ->
        mod = string_to_module(target)
        lookup_by_module(mod, modules_map, sources_map)
    end
  end

  defp lookup_by_file(path, modules_map, sources_map) do
    case sources_map[path] do
      nil ->
        IO.puts("\n## #{path}")
        IO.puts("NOT FOUND in manifest. File may not exist or hasn't been compiled yet.\n")
        []

      {:source, size, ts, _digest, compile_deps, runtime_deps, export_deps, _, _, _, _, defined_mods} ->
        IO.puts("\n## #{path}")
        IO.puts("Size: #{size} bytes | Last compiled: #{DateTime.from_unix!(ts)}")
        IO.puts("")

        defined = if is_list(defined_mods), do: defined_mods, else: Tuple.to_list(defined_mods)
        IO.puts("### Defines")
        for mod <- defined, do: IO.puts("  - #{inspect(mod)}")
        IO.puts("")

        print_deps("Compile-time dependencies", compile_deps, modules_map)
        print_deps("Runtime dependencies", runtime_deps, modules_map)
        print_deps("Export dependencies", export_deps, modules_map)

        defined
    end
  end

  defp lookup_by_module(mod, modules_map, sources_map) do
    case modules_map[mod] do
      nil ->
        IO.puts("\n## #{inspect(mod)}")
        IO.puts("NOT FOUND in manifest. Module may not exist or is from an external dependency.\n")
        []

      {:module, _, source_files, _digest, external?, ts} ->
        IO.puts("\n## #{inspect(mod)}")
        IO.puts("External: #{external?} | Last compiled: #{DateTime.from_unix!(ts)}")
        IO.puts("Source files: #{Enum.join(source_files, ", ")}")
        IO.puts("")

        # Now look up the source file(s) for full dependency info
        all_defined =
          for file <- source_files do
            case sources_map[file] do
              nil ->
                []
              {:source, _, _, _, compile_deps, runtime_deps, export_deps, _, _, _, _, defined_mods} ->
                print_deps("Compile-time dependencies", compile_deps, modules_map)
                print_deps("Runtime dependencies", runtime_deps, modules_map)
                print_deps("Export dependencies", export_deps, modules_map)

                if is_list(defined_mods), do: defined_mods, else: Tuple.to_list(defined_mods)
            end
          end
          |> List.flatten()

        # If the target module is in the list, return it; otherwise return all defined modules
        if mod in all_defined, do: [mod], else: all_defined
    end
  end

  defp print_reverse_deps(target_modules, _modules_map, sources_map) do
    target_set = MapSet.new(target_modules)

    dependents =
      for {file, {:source, _, _, _, compile_deps, runtime_deps, export_deps, _, _, _, _, _}} <- sources_map,
          all_deps = compile_deps ++ runtime_deps ++ export_deps,
          matching = Enum.filter(all_deps, &MapSet.member?(target_set, &1)),
          matching != [] do
        {file, matching}
      end
      |> Enum.sort_by(&elem(&1, 0))

    grouped =
      Enum.group_by(dependents, fn {path, _} ->
        cond do
          String.contains?(path, "test/") -> :test
          String.contains?(path, "live/") -> :liveview
          String.contains?(path, "controllers/") -> :controller
          String.contains?(path, "schema/") and String.contains?(path, "resolver") -> :graphql_resolver
          String.contains?(path, "schema/") and String.contains?(path, "type") -> :graphql_type
          String.contains?(path, "schema/") -> :graphql_other
          String.contains?(path, "workers/") -> :worker
          String.contains?(path, "lib/backend_web/") -> :web_other
          true -> :backend
        end
      end)

    IO.puts("### Depended on by (reverse dependencies)")
    IO.puts("")

    category_order = [:backend, :controller, :graphql_resolver, :graphql_type, :graphql_other, :liveview, :web_other, :worker, :test]

    for category <- category_order, Map.has_key?(grouped, category) do
      files = grouped[category]
      IO.puts("#### #{format_category(category)} (#{length(files)} files)")

      for {file, _deps} <- files do
        IO.puts("  - #{file}")
      end
      IO.puts("")
    end
  end

  defp format_category(:backend), do: "Backend (business logic)"
  defp format_category(:controller), do: "Controllers"
  defp format_category(:graphql_resolver), do: "GraphQL Resolvers"
  defp format_category(:graphql_type), do: "GraphQL Types"
  defp format_category(:graphql_other), do: "GraphQL Other"
  defp format_category(:liveview), do: "LiveViews"
  defp format_category(:web_other), do: "Web (plugs, components, helpers)"
  defp format_category(:worker), do: "Workers"
  defp format_category(:test), do: "Tests"

  defp print_deps(label, deps, modules_map) do
    {project, external} =
      Enum.split_with(deps, fn dep ->
        case modules_map[dep] do
          {:module, _, _, _, _, _} -> true
          _ -> false
        end
      end)

    project_with_files =
      Enum.map(project, fn dep ->
        {:module, _, files, _, _, _} = modules_map[dep]
        {dep, files}
      end)
      |> Enum.sort_by(fn {_, files} -> hd(files) end)

    IO.puts("### #{label} (#{length(project)} project, #{length(external)} external)")

    if project_with_files != [] do
      IO.puts("#### Project files to read:")
      for {mod, files} <- project_with_files do
        IO.puts("  - #{hd(files)}  (#{inspect(mod)})")
      end
    end

    if external != [] do
      IO.puts("#### External: #{Enum.map_join(Enum.sort(external), ", ", &inspect/1)}")
    end

    IO.puts("")
  end

  defp string_to_module(str) do
    # Handle both "Backend.Shifts" and "Elixir.Backend.Shifts"
    str = if String.starts_with?(str, "Elixir."), do: str, else: "Elixir." <> str
    String.to_atom(str)
  end
end

ManifestLookup.run(System.argv())
