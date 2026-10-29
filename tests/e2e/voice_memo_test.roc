# Real-browser E2E: the voice_memo example in Chromium with its fake
# microphone (a steady tone), the Media module on the real browser APIs:
# Media.stream asks for the microphone and opens it, Media.levels reports the
# tone's loudness while Media.record records, Media.finish hands the take
# over as a file, Media.audio_summary decodes its length and waveform,
# Media.object_url makes it playable, and Media.play, the element's own
# timeupdate events and Media.seek move it.
#
# Full Chromium, since the headless shell build has no media capture. Firefox
# and WebKit fake their devices differently, so this runs in Chromium only.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Duration
import pf.Sleep
import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Playwright.launch_page_with!(
		{ new: Cmd.new, os_str: OsStr.from_str, spawn!: Cmd.Command.spawn_leashed!, millis: Duration.millis },
		{
			browser_type: Chromium(Full),
			timeout: TimeoutMilliseconds(10000),
			args: ["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"],
			permissions: ["microphone"],
		},
	)?
	page.navigate!("${Browser.base_url!()}/voice_memo/")?
	assert!(page.find("#record").is_visible())?

	page.find("#record").click!()?
	assert!(page.find("#status").has_text("recording"))?

	# The fake microphone plays a tone, so the meter moves off zero.
	assert!(page.find("#level").matches_text("level [1-9]"))?

	Sleep.millis!(1500)?
	page.find("#stop").click!()?

	# A file of the container Chromium records, decoded to about the time
	# recorded, with the twenty peaks asked for.
	assert!(page.find("#status").has_text("idle"))?
	assert!(page.find("#memo-info").matches_text("memo\\.webm, [1-9][0-9]* bytes, [1-9][0-9]{2,} ms, 20 peaks"))?
	assert!(page.find("#waveform").matches_text("[▂▃▄▅▆▇█]"))?

	# Playback moves the position, and rewinding brings it back.
	page.find("#play").click!()?
	assert!(page.find("#position").matches_text("at [1-9][0-9]* ms"))?
	page.find("#pause").click!()?
	page.find("#rewind").click!()?
	assert!(page.find("#position").has_text("at 0 ms"))?

	browser.close!()?
	Ok({})
}
