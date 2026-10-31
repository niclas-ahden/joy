import pf.Env
import pf.System

## Where tests/e2e/compile.roc leaves each browser test, compiled once for every
## browser, as each one reads JOY_BROWSER when it runs.
Compiled :: [].{
	folder! : {} => Str
	folder! = |{}| "build/${Env.var_str!("JOY_OPT") ?? "speed"}/e2e"

	## The compiled form of the Roc file at `source`, a path from the repo root.
	binary! : Str => Str
	binary! = |source| {
		name = source.replace_each("\\", "/").drop_suffix(".roc").replace_each("/", "_")
		suffix =
			match System.target!().os() {
				Windows(_) => ".exe"
				_ => ""
			}
		"${folder!({})}/${name}${suffix}"
	}

	launcher_source : Str
	launcher_source = "tests/e2e/run_compiled.roc"
}
