files = Path.wildcard(Path.join(__DIR__, "lib/**/*.ex"))

{:ok, _, %{runtime_warnings: [], compile_warnings: []}} =
  Kernel.ParallelCompiler.compile(files, return_diagnostics: true)

Mix.Tasks.Dawarich.LegacyBuildInputs.run(System.argv())
