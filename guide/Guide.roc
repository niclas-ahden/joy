import /Topic/Welcome as TopicWelcome
import /Topic/FirstApp as TopicFirstApp
import /Topic/Loop as TopicLoop
import /Topic/Views as TopicViews
import /Topic/Effects as TopicEffects
import /Topic/Subscriptions as TopicSubscriptions
import /Topic/Flags as TopicFlags
import /Topic/Install as TopicInstall
import /Topic/CustomEffects as TopicCustomEffects
import html.Html
import /Doc
import /Topics

## A topic's body, from its module in Topic/.
Guide := [].{
	body : Topics.Topic -> Doc.Body
	body = |topic|
		match topic {
			Welcome => TopicWelcome.body
			FirstApp => TopicFirstApp.body
			Loop => TopicLoop.body
			Views => TopicViews.body
			Effects => TopicEffects.body
			Subscriptions => TopicSubscriptions.body
			Flags => TopicFlags.body
			Install => TopicInstall.body
			CustomEffects => TopicCustomEffects.body
		}
}
