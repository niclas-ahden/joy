## The Joy release this CLI belongs to: none in a checkout, and the one
## bundle-cli.roc names in the copy it bundles for a release.
Release :: [].{

	## The release's tag, such as 0.36.0, the URL of its platform bundle,
	## which the bundles of a project init starts name, and the URL of its
	## notes, which show the command that installs ./joy, since the CLI's own
	## URL holds a hash of the CLI.
	Release : { tag : Str, platform_url : Str, notes_url : Str }

	current = Unreleased

	## What ./joy --version prints: the release's tag, which bundle-cli.roc
	## writes here, or "unreleased" in a checkout. A string rather than a
	## match on `current`, which roc would warn is known at compile time.
	version : Str
	version = "unreleased"

	## Where init takes the platform from: the Joy checkout `checkout`
	## names, else this CLI's release. Matching on `current` itself would
	## make roc warn that the match is known at compile time.
	source : [Some(Str), None] -> [Checkout(Str), Published(Release.Release), Unreleased]
	source = |checkout|
		match checkout {
			Some(dir) => Checkout(dir)
			None => current
		}
}
