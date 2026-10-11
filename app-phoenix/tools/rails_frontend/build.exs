files = Path.wildcard(Path.join(__DIR__, "lib/**/*.ex"))
{:ok, _, []} = Kernel.ParallelCompiler.compile(files)
Mix.Tasks.Dawarich.LegacyBuildInputs.run(System.argv())
