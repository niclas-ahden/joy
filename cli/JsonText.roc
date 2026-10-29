## Just enough JSON to write assets.json and `./joy bundles --json`.
JsonText :: [].{
	string : Str -> Str
	string = |text| {
		escaped =
			Str.to_utf8(text)
				.map(escape_byte)
				.join()
		"\"${Str.from_utf8(escaped) ?? text}\""
	}

	object : List((Str, Str)) -> Str
	object = |fields|
		if fields.is_empty() {
			"{}"
		} else {
			"{ ${Str.join_with(fields.map(|(key, value)| "${string(key)}: ${value}"), ", ")} }"
		}

	array : List(Str) -> Str
	array = |items| "[${Str.join_with(items, ", ")}]"
}

escape_byte : U8 -> List(U8)
escape_byte = |byte|
	if byte == '"' {
		['\\', '"']
	} else if byte == '\\' {
		['\\', '\\']
	} else if byte == '\n' {
		['\\', 'n']
	} else if byte == '\r' {
		['\\', 'r']
	} else if byte == '\t' {
		['\\', 't']
	} else if byte < 0x20 {
		hex = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']
		['\\', 'u', '0', '0', hex.get((byte // 16).to_u64()) ?? '0', hex.get((byte % 16).to_u64()) ?? '0']
	} else {
		[byte]
	}
