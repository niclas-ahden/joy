## Every topic of the guide in reading order, and what the index knows of
## each. A topic's body is in Topic/, one module per topic (see Guide).
Topics := [].{
	Topic : [
		Welcome,
		FirstApp,
		Effects,
		Views,
		Loop,
		Subscriptions,
		Flags,
		Install,
		CustomEffects,
	]

	## What the index shows of a topic, and finds it by: its #anchor, the part
	## of the guide it is in, its title and the words a search matches.
	Info : { id : Str, part : Str, title : Str, keywords : Str }

	all : List(Topic)
	all = [
		Welcome,
		FirstApp,
		Effects,
		Views,
		Loop,
		Subscriptions,
		Flags,
		Install,
		CustomEffects,
	]

	info : Topic -> Info
	info = |topic|
		match topic {
			Welcome => { id: "welcome", part: "Start here", title: "What is Joy?", keywords: "intro overview roc wasm webassembly elm architecture platform runtime" }
			FirstApp => { id: "first-app", part: "Start here", title: "Your first app", keywords: "header app counter model msg init update view render subscriptions platform" }
			Loop => { id: "loop", part: "Start here", title: "Enough to be dangerous", keywords: "recap summary basics update loop elm architecture tea cycle view render effects messages flow" }
			Views => { id: "views", part: "Start here", title: "Views", keywords: "html attribute joy-html events on_click on_input map inert msg" }
			Effects => { id: "effects", part: "Start here", title: "Effects", keywords: "http time debounce dom modal title scroll clipboard console port webcrypto media effect map" }
			Subscriptions => { id: "subscriptions", part: "Start here", title: "Subscriptions", keywords: "sub time every keyboard on_down_keys listen map" }
			Flags => { id: "flags", part: "Start here", title: "Flags", keywords: "flags init mount json parse javascript start data" }
			Install => { id: "install", part: "Installation", title: "Joy on your machine", keywords: "install installation setup get started roc nightly init template spa new project joy dev hot reload build dist" }
			CustomEffects => { id: "custom-effects", part: "Reference", title: "Custom effects", keywords: "custom effects own javascript js browser api package effects folder effect call send sub listen wire defineEffect defineSubscription operation id share network online offline interop ffi port" }
		}

	## Where a topic is in reading order, counting from 0.
	position : Topic -> U64
	position = |topic| {
		var $at = 0
		var $found = 0
		for t in all {
			if t == topic {
				$found = $at
			} else {
				{}
			}
			$at = $at + 1
		}
		$found
	}

	## The topic just before or after this one.
	neighbour : Topic, [Before, After] -> Try(Topic, [NoNeighbour])
	neighbour = |topic, side| {
		at = position(topic)
		match side {
			Before => if (at == 0) Err(NoNeighbour) else all.get(at - 1).map_err(|_| NoNeighbour)
			After => all.get(at + 1).map_err(|_| NoNeighbour)
		}
	}
}
