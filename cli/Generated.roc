import pf.Path
import Project
import "generated/Names.txt" as names_template : Str

## The generated/ package: `Bundle`, `Asset`, `Public` and `Names`, made from
## the bundle files and the lists of files in assets/ and public/ alone,
## before anything compiles, so the server and the bundles build at the same
## time. ./joy writes it only when a header in the project names it, and
## each file only when its content changes, so nothing watching it wakes for
## nothing.
Generated :: [].{

	## Whether a header in the project names the package.
	named! : () => Try(Bool, _)
	named! = || {
		roc_files = Project.project_roc_files!()?
		roc_files.fold_try!(False, |found, file| if (found) Ok(True) else Ok(header_names_it!(file)))
	}

	## The package's files, by name, with `assets` giving each file in
	## assets/ its path: its own name while you work, a hashed one in a build.
	files : List(Project.Bundle), List((Str, Str)), List(Str), Str -> Try(List((Str, Str)), [SameTag(Str, Str)])
	files = |bundles, assets, public, client_url| {
		tags = bundles.map(|bundle| bundle.tag)
		for bundle in bundles {
			match bundles.find_first(|other| other.tag == bundle.tag and other.id != bundle.id) {
				Ok(other) => return Err(SameTag(bundle.id, other.id))
				Err(_) => {}
			}
		}
		Ok([
			("main.roc", main_source),
			("Bundle.roc", bundle_source(bundles, tags)),
			("Asset.roc", asset_source(assets, client_url)),
			("Public.roc", public_source(public, client_url)),
			("Names.roc", names_template.replace_each("client_url = \"/\"", "client_url = ${quoted(client_url)}")),
		])
	}

	## Whether the app or package in `file` depends on the package, itself or
	## through a package it names by path. roc refuses to replace a package a
	## build does not use, so only these builds get the build's copy.
	used_by! : Str => Bool
	used_by! = |file| uses!(file, [])

	## Write the package into `dir`, each file only when it changed. Returns
	## whether anything did.
	write! : Str, List((Str, Str)) => Try(Bool, _)
	write! = |dir, contents| {
		Path.utf8(dir).create_all!()?
		contents.fold_try!(
			False,
			|changed, (name, content)| {
				path = Path.utf8("${dir}/${name}")
				if (path.read_utf8!() ?? "") == content {
					Ok(changed)
				} else {
					path.write_utf8!(content)?
					Ok(True)
				}
			},
		)
	}
}

header_names_it! : Str => Bool
header_names_it! = |file| {
	header = header_of!(file)
	(header.starts_with("app") or header.contains("\napp ") or header.contains("\napp[") or header.starts_with("package") or header.contains("\npackage ")) and header.contains("generated/main.roc\"")
}

main_source =
	\\## Written by ./joy from client/, assets/ and public/: do not edit. ./joy
	\\## writes it again when a bundle or a file is added, renamed or removed.
	\\package [Asset, Bundle, Names, Public] {}
	\\

## A Roc string literal of `text`.
quoted : Str -> Str
quoted = |text| "\"${text.replace_each("\\", "\\\\").replace_each("\"", "\\\"").replace_each("$", "\\$")}\""

bundle_source : List(Project.Bundle), List(Str) -> Str
bundle_source = |bundles, tags| {
	header = "## The bundles under client/, by id. Written by ./joy: do not edit.\n"
	if bundles.is_empty() {
		Str.join_with(
			[
				header,
				"Bundle := [].{\n",
				"\t## The bundle's id: its path below client/, without the extension.\n",
				"\tpath : Bundle -> Str\n",
				"\tpath = |_bundle| \"\"\n\n",
				"\tall : List(Bundle)\n",
				"\tall = []\n",
				"}\n",
			],
			"",
		)
	} else {
		branches = Str.join_with(bundles.map(|bundle| "\t\t\t${bundle.tag} => ${quoted(bundle.id)}\n"), "")
		Str.join_with(
			[
				header,
				"Bundle := [${Str.join_with(tags, ", ")}].{\n\n",
				"\t## The bundle's id: its path below client/, without the extension.\n",
				"\tpath : Bundle -> Str\n",
				"\tpath = |bundle|\n",
				"\t\tmatch bundle {\n",
				branches,
				"\t\t}\n\n",
				"\tall : List(Bundle)\n",
				"\tall = [${Str.join_with(tags, ", ")}]\n",
				"}\n",
			],
			"",
		)
	}
}

asset_source : List((Str, Str)), Str -> Str
asset_source = |assets, client_url| {
	all =
		if assets.is_empty() {
			"\tall = []\n"
		} else {
			"\tall = [\n${Str.join_with(assets.map(|(name, path)| "\t\t(${quoted(name)}, ${quoted(path)}),\n"), "")}\t]\n"
		}
	Str.join_with(
		[
			"## The files in assets/. A name in quotes where an `Asset` is expected is\n",
			"## checked while compiling, `\"css/site.css\"`, and a file that does not exist\n",
			"## is a compile error. Written by ./joy: do not edit.\n",
			"Asset := [Asset(Str, Str)].{\n",
			"\tfrom_quote : Str -> Try(Asset, [BadQuotedBytes(Str)])\n",
			"\tfrom_quote = |name|\n",
			"\t\tmatch all.find_first(|(file, _)| file == name) {\n",
			"\t\t\tOk((file, path)) => Ok(Asset(file, path))\n",
			"\t\t\tErr(_) => Err(BadQuotedBytes(\"There is no file assets/\${name}.\"))\n",
			"\t\t}\n\n",
			"\t## The file's path below the client URL: its plain name while you work,\n",
			"\t## and its hashed name in a build.\n",
			"\tpath : Asset -> Str\n",
			"\tpath = |Asset(_, file)| file\n\n",
			"\t## The file's URL: its path below the client URL, JOY_CLIENT_URL.\n",
			"\turl : Asset -> Str\n",
			"\turl = |Asset(_, file)| Str.concat(${quoted(client_url)}, file)\n\n",
			"\t## The file's name in assets/.\n",
			"\tname : Asset -> Str\n",
			"\tname = |Asset(file, _)| file\n\n",
			"\t## Every file in assets/, by name and path.\n",
			"\tall : List((Str, Str))\n",
			all,
			"}\n",
		],
		"",
	)
}

public_source : List(Str), Str -> Str
public_source = |public, client_url| {
	all =
		if public.is_empty() {
			"\tall = []\n"
		} else {
			"\tall = [\n${Str.join_with(public.map(|file| "\t\t${quoted(file)},\n"), "")}\t]\n"
		}
	Str.join_with(
		[
			"## The files in public/, served by the names they have. A name in quotes\n",
			"## where a `Public` is expected is checked while compiling. Written by\n",
			"## ./joy: do not edit.\n",
			"Public := [Public(Str)].{\n",
			"\tfrom_quote : Str -> Try(Public, [BadQuotedBytes(Str)])\n",
			"\tfrom_quote = |name|\n",
			"\t\tif (all.contains(name)) Ok(Public(name)) else Err(BadQuotedBytes(\"There is no file public/\${name}.\"))\n\n",
			"\t## The file's path below the client URL.\n",
			"\tpath : Public -> Str\n",
			"\tpath = |Public(file)| file\n\n",
			"\t## The file's URL: its path below the client URL, JOY_CLIENT_URL.\n",
			"\turl : Public -> Str\n",
			"\turl = |Public(file)| Str.concat(${quoted(client_url)}, file)\n\n",
			"\t## Every file in public/.\n",
			"\tall : List(Str)\n",
			all,
			"}\n",
		],
		"",
	)
}

uses! : Str, List(Str) => Bool
uses! = |file, seen|
	if seen.contains(file) {
		False
	} else {
		folder =
			match file.split_last("/") {
				Ok({ before, .. }) => before
				Err(_) => "."
			}
		package_paths(header_of!(file)).any(
			|path|
				if path.ends_with("generated/main.roc") {
					True
				} else {
					uses!("${folder}/${path}", seen.append(file))
				},
		)
	}

header_of! : Str => Str
header_of! = |file| {
	source = Str.from_utf8_lossy(Path.utf8(file).read_bytes!() ?? [])
	match source.split_first("\nimport ") {
		Ok({ before, .. }) => before
		Err(_) => source
	}
}

## The packages a header names by path: quoted values ending in main.roc
## that are not URLs.
package_paths : Str -> List(Str)
package_paths = |header|
	header
		.split_on("\"")
		.keep_if(|part| part.ends_with("main.roc") and !part.contains("://"))
