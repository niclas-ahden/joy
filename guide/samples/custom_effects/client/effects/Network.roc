import pf.Sub
import pf.Wire

## Whether the browser has a connection. Its JavaScript is Network.js beside
## this file.
Network := [].{
	Status : [Online, Offline]

	## Hear when the browser gains or loses its connection.
	on_change : (Status -> msg) -> Sub(msg)
	on_change = |to_msg| Sub.listen("my_app/network_changes", [], |event| to_msg(status(event)))
}

status : List(U8) -> Network.Status
status = |event| {
	online = Wire.reader(event).bool().map_ok(|(is_online, _)| is_online) ?? False
	if (online) Online else Offline
}

expect status(Wire.writer({}).bool(Bool.True).done()) == Online
expect status(Wire.writer({}).bool(Bool.False).done()) == Offline
