# Usage:
#   elixir scripts/manifest_tree.exs [--depth N] [namespace] [manifest_path]
#
# Shows the module namespace tree from the compile manifest.
# If a namespace is given, only shows that subtree.
# If --depth N is given, limits tree depth and shows module counts for collapsed branches.
#
# Examples:
#   elixir scripts/manifest_tree.exs                          # full tree
#   elixir scripts/manifest_tree.exs --depth 2                # top-level namespaces only
#   elixir scripts/manifest_tree.exs Backend.Accounts         # just the Accounts subtree
#   elixir scripts/manifest_tree.exs --depth 1 Backend        # Backend's immediate children

defmodule ManifestTree do
  def run(args) do
    {namespace, max_depth, manifest_path} = parse_args(args)

    data = File.read!(manifest_path)
    term = :erlang.binary_to_term(data)
    modules_map = elem(term, 1)

    modules =
      modules_map
      |> Enum.filter(fn {_mod, {:module, _, _, _, external?, _}} -> not external? end)
      |> Enum.map(fn {mod, {:module, _, files, _, _, _}} ->
        name = mod |> Atom.to_string() |> String.replace_leading("Elixir.", "")
        file = List.first(files)
        {name, file}
      end)
      |> Enum.filter(fn {name, _} ->
        case namespace do
          nil -> true
          ns -> name == ns or String.starts_with?(name, ns <> ".")
        end
      end)
      |> Enum.sort_by(&elem(&1, 0))

    if modules == [] do
      IO.puts("No modules found#{if namespace, do: " under #{namespace}", else: ""}.")
    else
      tree = build_tree(modules)

      label = namespace || "Project"
      IO.puts("## #{label} namespace (#{length(modules)} modules)\n")
      print_tree(tree, "", max_depth, 0)
    end
  end

  defp build_tree(modules) do
    Enum.reduce(modules, %{}, fn {name, file}, acc ->
      parts = String.split(name, ".")
      put_in_tree(acc, parts, file)
    end)
  end

  defp put_in_tree(tree, [leaf], file) do
    Map.update(tree, leaf, {:leaf, file, %{}}, fn
      {:leaf, existing_file, children} -> {:leaf, existing_file, children}
      {:branch, children} -> {:leaf, file, children}
    end)
  end

  defp put_in_tree(tree, [head | tail], file) do
    Map.update(tree, head, {:branch, put_in_tree(%{}, tail, file)}, fn
      {:leaf, existing_file, children} -> {:leaf, existing_file, put_in_tree(children, tail, file)}
      {:branch, children} -> {:branch, put_in_tree(children, tail, file)}
    end)
  end

  defp print_tree(tree, indent, max_depth, current_depth) do
    entries = Enum.sort_by(tree, &elem(&1, 0))
    last_idx = length(entries) - 1

    entries
    |> Enum.with_index()
    |> Enum.each(fn {{name, node}, idx} ->
      is_last = idx == last_idx
      connector = if is_last, do: "└── ", else: "├── "
      child_indent = indent <> if(is_last, do: "    ", else: "│   ")

      children = get_children(node)
      at_depth_limit = max_depth != nil and current_depth >= max_depth

      cond do
        at_depth_limit and map_size(children) > 0 ->
          count = count_modules(node)
          IO.puts("#{indent}#{connector}#{name}/ (#{count} modules)")

        at_depth_limit ->
          case node do
            {:leaf, file, _} -> IO.puts("#{indent}#{connector}#{name}  (#{file})")
            {:branch, _} -> IO.puts("#{indent}#{connector}#{name}/")
          end

        true ->
          case node do
            {:leaf, file, c} when map_size(c) > 0 ->
              IO.puts("#{indent}#{connector}#{name}  (#{file})")
              print_tree(c, child_indent, max_depth, current_depth + 1)

            {:leaf, file, _} ->
              IO.puts("#{indent}#{connector}#{name}  (#{file})")

            {:branch, c} ->
              IO.puts("#{indent}#{connector}#{name}/")
              print_tree(c, child_indent, max_depth, current_depth + 1)
          end
      end
    end)
  end

  defp get_children({:leaf, _, children}), do: children
  defp get_children({:branch, children}), do: children

  defp count_modules({:leaf, _, children}) do
    1 + count_children(children)
  end

  defp count_modules({:branch, children}) do
    count_children(children)
  end

  defp count_children(children) do
    Enum.reduce(children, 0, fn {_, node}, acc ->
      acc + count_modules(node)
    end)
  end

  defp parse_args(args) do
    {depth, rest} = extract_depth(args, nil, [])

    case rest do
      [] -> {nil, depth, find_manifest()}
      [ns] -> {ns, depth, find_manifest()}
      [ns, manifest] -> {ns, depth, manifest}
    end
  end

  defp extract_depth(["--depth", n | rest], _depth, acc) do
    extract_depth(rest, String.to_integer(n), acc)
  end

  defp extract_depth([arg | rest], depth, acc) do
    extract_depth(rest, depth, acc ++ [arg])
  end

  defp extract_depth([], depth, acc), do: {depth, acc}

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

ManifestTree.run(System.argv())
