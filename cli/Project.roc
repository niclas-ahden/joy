import pf.Env
import pf.Path
import pf.System

## A Joy project as ./joy sees it from the directory it runs in: the bundles
## under client/, found by their headers, and the server, server/main.roc.
##
## A bundle is a .roc file whose header is an app on Joy's platform. Its id is
## its path below client/ without the extension, so adding or removing a file
## never renames another bundle. The searches skip dot folders, symlinks and
## the folders ./joy writes.
Project :: [].{
	Bundle : { id : Str, tag : Str, file : Str, joy : Str }

	## The bundles under client/, sorted by id, and the Joy apps elsewhere in
	## the project, which are found but not built.
	find! : () => Try({ bundles : List(Bundle), strays : List(Str) }, _)
	find! = || {
		bundles =
			if Path.utf8("client").is_dir!() ?? False {
				files = roc_files!("client", [])?
				var $found = []
				for file in files {
					match bundle_of!(file) {
						Ok(bundle) => {
							$found = $found.append(bundle)
						}
						Err(_) => {}
					}
				}
				$found
			} else {
				[]
			}
		others = roc_files!(".", ["client", "dist", ".joy", "node_modules", "target", "result"])?
		strays = others.keep_if_try!(|file| Ok((joy_app!(file) ?? None) != None))?.map(|file| file.drop_prefix("./"))
		Ok({ bundles: List.sort_with(bundles, |a, b| compare(a.id, b.id)), strays })
	}

	## Every .roc file in the project, apart from the folders ./joy writes.
	project_roc_files! : () => Try(List(Str), _)
	project_roc_files! = || {
		files = roc_files!(".", ["dist", ".joy", "node_modules", "target", "result"])?
		Ok(files.map(|file| file.drop_prefix("./")))
	}

	## The project's server, when it has one.
	server! : () => [Some(Str), None]
	server! = ||
		if Path.utf8("server/main.roc").is_file!() ?? False {
			Some("server/main.roc")
		} else {
			None
		}

	## Byte order, the order bundles and files are listed in, so a listing
	## is the same on every machine.
	order : Str, Str -> [Before, Same, After]
	order = |a, b| compare(a, b)

	## The id of the bundle in `file`, a path below client/.
	id_of : Str -> Str
	id_of = |file| file.drop_prefix("client/").drop_suffix(".roc")

	## The tag the generated package gives a bundle: its id's words, each
	## capitalized, `Checkout/cart` as `CheckoutCart`.
	tag_of : Str -> Str
	tag_of = |id|
		Str.join_with(
			id
				.split_on("/")
				.join_map(|part| part.split_on("_"))
				.join_map(|part| part.split_on("-"))
				.map(capitalize),
			"",
		)

	## The platform an app header names, whatever its shorthand, when the
	## source is an app.
	header_platform : Str -> [Some(Str), None]
	header_platform = |source| {
		lines = drop_leading_comments(source.split_on("\n"))
		rest = Str.join_with(lines, "\n").trim_start()
		if rest.starts_with("app ") or rest.starts_with("app[") {
			header =
				match rest.split_first("\nimport ") {
					Ok({ before, .. }) => before
					Err(_) => rest
				}
			match header.split_first("platform \"") {
				Ok({ after, .. }) =>
					match after.split_first("\"") {
						Ok({ before, .. }) => Some(before)
						Err(_) => None
					}

				Err(_) => None
			}
		} else {
			None
		}
	}

	## Whether a platform named from `file` is Joy's: a release URL of Joy, or a
	## path to a Joy checkout, where www/runtime.js sits beside platform/.
	is_joy! : Str, Str => Bool
	is_joy! = |file, named|
		if is_url(named) {
			named.with_ascii_lowercased().contains("/joy/")
		} else {
			Path.utf8("${platform_dir(file, named)}/../www/runtime.js").is_file!() ?? False
		}

	## Where the runtime's sources are for a bundle: www/ beside the platform
	## of a checkout, or in roc's package cache for a release, once roc has
	## fetched it.
	www! : Bundle => Str
	www! = |bundle|
		if is_url(bundle.joy) {
			hash =
				match bundle.joy.split_last("/") {
					Ok({ after, .. }) => after.drop_suffix(".tar.zst")
					Err(_) => bundle.joy.drop_suffix(".tar.zst")
				}
			"${package_cache!()}/${hash}/www"
		} else {
			"${platform_dir(bundle.file, bundle.joy)}/../www"
		}

	## The checkout a path platform belongs to, for building its host.
	checkout : Bundle -> [Some(Str), None]
	checkout = |bundle|
		if is_url(bundle.joy) {
			None
		} else {
			Some("${platform_dir(bundle.file, bundle.joy)}/..")
		}
}

is_url : Str -> Bool
is_url = |named| named.starts_with("https://") or named.starts_with("http://")

## The folder of a path platform's main.roc, as a path from the project root.
platform_dir : Str, Str -> Str
platform_dir = |file, named| {
	folder =
		match file.split_last("/") {
			Ok({ before, .. }) => before
			Err(_) => "."
		}
	main =
		match named.split_last("/") {
			Ok({ before, .. }) => before
			Err(_) => "."
		}
	"${folder}/${main}"
}

bundle_of! : Str => Try(Project.Bundle, [NotABundle])
bundle_of! = |file|
	match joy_app!(file) {
		Ok(Some(named)) => {
			id = Project.id_of(file)
			Ok({ id, tag: Project.tag_of(id), file, joy: named })
		}
		_ => Err(NotABundle)
	}

## The platform of a Joy app in `file`, or `None` for any other file.
joy_app! : Str => Try([Some(Str), None], _)
joy_app! = |file| {
	source = Str.from_utf8_lossy(Path.utf8(file).read_bytes!()?)
	match Project.header_platform(source) {
		Some(named) =>
			if Project.is_joy!(file, named) {
				Ok(Some(named))
			} else {
				Ok(None)
			}

		None => Ok(None)
	}
}

## Every .roc file below `dir`, skipping dot folders, symlinks and the folders
## named in `skip`.
roc_files! : Str, List(Str) => Try(List(Str), _)
roc_files! = |dir, skip| {
	entries = Path.utf8(dir).list!()?
	entries.fold_try!(
		[],
		|found, entry| {
			path = Path.display(entry)
			name =
				match path.split_last("/") {
					Ok({ after, .. }) => after
					Err(_) => path
				}
			if name.starts_with(".") {
				Ok(found)
			} else {
				match entry.type!()? {
					IsDir =>
						if skip.contains(name) {
							Ok(found)
						} else {
							Ok(found.concat(roc_files!(path, [])?))
						}

					IsFile =>
						if name.ends_with(".roc") {
							Ok(found.append(path))
						} else {
							Ok(found)
						}

					_ => Ok(found)
				}
			}
		},
	)
}

drop_leading_comments : List(Str) -> List(Str)
drop_leading_comments = |lines|
	match lines {
		[line, .. as rest] =>
			if line.trim().is_empty() or line.trim_start().starts_with("#") {
				drop_leading_comments(rest)
			} else {
				lines
			}

		[] => []
	}

capitalize : Str -> Str
capitalize = |word|
	match Str.to_utf8(word) {
		[first, .. as rest] if first >= 'a' and first <= 'z' => Str.from_utf8([first - 32].concat(rest)) ?? word
		_ => word
	}

compare : Str, Str -> [Before, Same, After]
compare = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_bytes(xs, ys)
	}

## Where roc keeps the packages it downloads, found the way roc finds it.
package_cache! : () => Str
package_cache! = || {
	base =
		match Env.var_str!("XDG_CACHE_HOME") {
			Ok(xdg) => xdg
			Err(_) =>
				match (System.target!().os(), Env.var_str!("LOCALAPPDATA")) {
					(Windows(_), Ok(local)) => local
					_ => "${Env.var_str!("HOME") ?? ""}/.cache"
				}
		}
	"${base}/roc/packages"
}
