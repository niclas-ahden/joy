import pf.Env
import pf.Path
import pf.Stderr
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
				files = roc_files!("client", [], Stop)?
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
		others = roc_files!(".", ["client", "dist", ".joy", "node_modules", "target", "result"], Skip)?
		strays = others.keep_if_try!(|file| Ok((joy_app!(file) ?? None) != None))?.map(|file| file.drop_prefix("./"))
		Ok({ bundles: List.sort_with(bundles, |a, b| compare(a.id, b.id)), strays })
	}

	## Every .roc file in the project, apart from the folders ./joy writes.
	## Stop with a message that names the file, for one in the project ./joy cannot use.
	could_not! : Str, _ => Try(_ok, [Exit(I32)])
	could_not! = |what, err| {
		detail = Str.inspect(err)
		reason = if (detail.contains("PermissionDenied")) "permission denied" else detail
		Stderr.line!("Could not ${what}: ${reason}") ?? {}
		Err(Exit(1))
	}

	project_roc_files! : () => Try(List(Str), _)
	project_roc_files! = || {
		files = roc_files!(".", ["dist", ".joy", "node_modules", "target", "result"], Skip)?
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

	## Whether a bundle's tag can be written in generated/Bundle.roc: a capital
	## letter, then letters and digits.
	valid_tag : Str -> Bool
	valid_tag = |tag|
		match Str.to_utf8(tag) {
			[first, .. as rest] => first >= 'A' and first <= 'Z' and rest.all(|byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9'))
			[] => False
		}

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

	## The packages an app header names besides its platform, as written.
	header_packages : Str -> List(Str)
	header_packages = |source| {
		header =
			match source.split_first("\nimport ") {
				Ok({ before, .. }) => before
				Err(_) => source
			}
		parts = header.split_on("\"")
		# Every second part is the text of a string, and the part before it
		# says whether that string is the platform's.
		parts
			.map_with_index(|part, index| (part, index))
			.keep_if(|(_, index)| index % 2 == 1)
			.keep_if(|(_, index)| !(parts.get(index - 1) ?? "").trim_end().ends_with("platform"))
			.map(|(part, _)| part)
	}

	## The folders of the packages the bundles name, and of the packages those
	## name in turn, each once: a package's folder in a checkout, or in roc's
	## package cache for a release.
	package_folders! : List(Bundle) => List(Str)
	package_folders! = |bundles| {
		var $found = []
		var $left = bundles.map(|bundle| bundle.file)
		while !$left.is_empty() {
			file = $left.first() ?? ""
			$left = $left.drop_first(1)
			source = Str.from_utf8_lossy(Path.utf8(file).read_bytes!() ?? [])
			for named in Project.header_packages(source) {
				folder =
					if is_url(named) {
						hash =
							match named.split_last("/") {
								Ok({ after, .. }) => after.drop_suffix(".tar.zst")
								Err(_) => named.drop_suffix(".tar.zst")
							}
						"${package_cache!()}/${hash}"
					} else {
						platform_dir(file, named)
					}
				# One folder can be named by many paths.
				real = Path.utf8(folder).canonicalize!().map_ok(Path.display) ?? folder
				if !$found.any(|(_, known)| known == real) and (Path.utf8(folder).is_dir!() ?? False) {
					$found = $found.append((folder, real))
					$left = $left.append("${folder}/main.roc")
				}
			}
		}
		$found.map(|(folder, _)| folder)
	}

	## The JavaScript file of a Roc module, for the custom effects it
	## calls: the one of its name beside it. `Greeter.roc` has `Greeter.js`.
	script_of : Str -> Str
	script_of = |file| "${file.drop_suffix(".roc")}.js"

	## The JavaScript of browser features besides Joy's own: the files there
	## are for the modules of the project and of its packages, see [script_of].
	feature_files! : List(Bundle) => List(Str)
	feature_files! = |bundles|
		own_sources!(bundles)
			.map(Project.script_of)
			.keep_if_try!(|file| Ok(Path.utf8(file).is_file!() ?? False))
			?? []

	## The Roc files a bundle is made of, apart from the builtins: the
	## project's own under client/, its packages' and its platform's. Each
	## with `home`, the file the JavaScript of its effects belongs in.
	bundle_sources! : List(Bundle) => List({ file : Str, home : Str })
	bundle_sources! = |bundles| {
		var $platforms = []
		for bundle in bundles {
			its_platform = Project.platform!(bundle)
			if !$platforms.any(|(folder, _)| folder == its_platform) {
				$platforms = $platforms.append((its_platform, Project.www!(bundle)))
			}
		}
		# Joy keeps the JavaScript of its own modules together.
		of_platforms =
			$platforms
				.map_try!(|(folder, www)| Ok((roc_files!(folder, [], Skip) ?? []).map(|file| { file, home: "${www}/features/${file_name(file).drop_suffix(".roc").with_ascii_lowercased()}.js" })))
				.map_ok(|found| found.join())
				?? []
		own_sources!(bundles).map(|file| { file, home: Project.script_of(file) }).concat(of_platforms)
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

	## The folder of a bundle's platform: in a checkout, or in roc's package
	## cache for a release, once roc has fetched it.
	platform! : Bundle => Str
	platform! = |bundle|
		if is_url(bundle.joy) {
			www!(bundle).drop_suffix("/www")
		} else {
			platform_dir(bundle.file, bundle.joy)
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
## named in `skip`. A folder that cannot be read stops the search with a
## message, or is skipped: client/ has to be read, and the rest of the project
## may hold folders that are not ./joy's to read, a database's files say.
roc_files! : Str, List(Str), [Stop, Skip] => Try(List(Str), _)
roc_files! = |dir, skip, unreadable| {
	entries =
		match Path.utf8(dir).list!() {
			Ok(found) => found
			Err(_) if unreadable == Skip => return Ok([])
			Err(err) => return Project.could_not!("read ${dir.drop_prefix("./")}/", err)
		}
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
				kind =
					match entry.type!() {
						Ok(known) => known
						# Gone since it was listed, like an editor's temporary file.
						Err(_) if unreadable == Skip => return Ok(found)
						Err(err) => return Project.could_not!("read ${path.drop_prefix("./")}", err)
					}
				match kind {
					IsDir =>
						if skip.contains(name) {
							Ok(found)
						} else {
							Ok(found.concat(roc_files!(path, [], unreadable)?))
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

## The Roc files of a project's client/ and of the packages its bundles name,
## each once: a package that bundles share can sit under client/ itself.
own_sources! : List(Project.Bundle) => List(Str)
own_sources! = |bundles| {
	files =
		["client"]
			.concat(Project.package_folders!(bundles))
			.map_try!(|folder| Ok(roc_files!(folder, [], Skip) ?? []))
			.map_ok(|found| found.join())
			?? []
	var $found = []
	for file in files {
		real = Path.utf8(file).canonicalize!().map_ok(Path.display) ?? file
		if !$found.any(|(_, known)| known == real) {
			$found = $found.append((file, real))
		}
	}
	$found.map(|(file, _)| file)
}

file_name : Str -> Str
file_name = |path|
	match path.split_last("/") {
		Ok({ after, .. }) => after
		Err(_) => path
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

expect Project.valid_tag("CheckoutCart")
expect Project.valid_tag("App2")
expect !Project.valid_tag("2fa")
expect !Project.valid_tag("My.page")
expect !Project.valid_tag("Élan")
expect !Project.valid_tag("")

expect Project.header_packages("app [main] {\n\tpf: platform \"../platform/main.roc\",\n\thtml: \"https://example.com/html.tar.zst\",\n\tstore: \"../store/package/main.roc\",\n}\n\nimport pf.Effect\nlabel = \"not a package\"") == ["https://example.com/html.tar.zst", "../store/package/main.roc"]
expect Project.header_packages("app [main] { pf: platform \"p\" }") == []
