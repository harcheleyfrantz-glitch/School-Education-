class_name CommentBank
extends RefCounted
## Extra lines for generated comment threads, by tone (more than 500), plus how people answer
## the player's own comments. Placeholders are filled from NewsComments facts ({airline},
## {num}, {short}, {type}, {place}, {fatal}, {aboard}, {from}, {to}, {pilot}, {outlet}...).

const LINES := {
	"condolence": [
		"Flags at half mast at {from} airport today.", "I keep refreshing the news hoping the number goes down.", "The whole of {to} is in mourning.", "I didn't know anyone on board and I still can't stop crying.", "Forever 30,000 feet closer to heaven.", "Thinking of the air traffic controllers who were working that night too.", "No family should have to identify a loved one like this.", "May their memory be a blessing.", "Such a senseless loss.", "We'll walk past the memorial every day and remember.", "Strength to the families. The whole country is with you.", "Everyone at my office stopped working when the news broke.", "I can't stop thinking about the last messages they sent home.", "Grief has no words. Just love.", "Thank you to the hospital staff working all night.",
		"I can't imagine what the families of {num} are going through tonight.", "Lighting a candle for everyone on {num}.",
		"Every flight I take from now on I'll think of the people on {num}.", "My thoughts are with the crew's colleagues at {airline}. This hits the whole industry.",
		"So many futures gone in a few seconds.", "The photos from {place} are unbearable.", "Prayers for the survivors and for the ones still waiting for news.",
		"We are a small country. Everybody knows someone who knows someone on that plane.", "Hug your people. Call your mum. Life is short.",
		"I hope they find answers, for the families' sake.", "There will be empty chairs at a lot of tables tonight.", "Devastated. Just devastated.",
		"Rest easy, {num}. You won't be forgotten.", "{fatal} people who just wanted to get to {to}.", "Thinking of the first responders too. They'll carry this forever.",
		"The church bells in {place} rang all evening.", "Not a single word is enough for this.", "Holding everyone affected in my heart.",
		"I flew {from} to {to} last week. I keep thinking it could have been any of us.", "The schools in {place} are bringing in counsellors tomorrow.",
		"May the families find some peace one day.", "I've been crying since I saw the news.", "Gone too soon, every single one of them.",
		"Condolences from all of us at the flying club.", "Remember their names, not the wreckage.", "My heart breaks for the children who lost parents today.",
	],
	"survived": [
		"They should make a film about that evacuation.", "I've never been so happy to read 'no fatalities'.", "Ninety seconds to get everyone out. Textbook.", "The man helping the old lady down the slide is the real hero.", "I'm flying {airline} again next week and I feel safer, honestly.", "Credit to the passengers too, they listened to the crew.", "A burned-out wreck and everyone walked away. Unbelievable.", "Hope the crew get time off and proper support.", "They kept the wings level all the way down.", "Survivors told reporters the crew never raised their voices.", "Somebody give that cabin crew a pay rise.", "Modern aviation is astonishing.", "The over-wing exits worked perfectly.", "I want to shake the hand of every firefighter there.", "A miracle on the outskirts of {place}.",
		"{aboard} people get to go home tonight. That's all that matters.", "That airframe did its job. Credit to the engineers at {maker}.",
		"Watching the evacuation footage, the crew had everyone out fast.", "Seat belts, brace position, calm crew. That's how you survive.",
		"I'd frame that boarding pass if I were on it.", "Lucky doesn't even begin to describe it.", "The fire crews were there before the slides were fully inflated.",
		"Every passenger should have to watch this before they ignore the safety demo.", "Bruises and broken bones heal. Everyone is alive.",
		"The cabin crew on {num} deserve every award going.", "That {short} took a beating and protected everyone inside.",
		"Pictures look terrible but zero fatalities. Remarkable.", "I hope the survivors get proper support. The trauma lasts.",
		"Imagine calling home to say 'I'm fine, but the plane isn't'.", "Proof that the boring safety rules matter.",
		"The pilots kept it straight. Look how the wreck sits on the ground.", "Glad to see the injured are recovering at {place} hospital.",
		"This is going to be studied in training for years.", "Whoever designed those seats saved lives today.", "Somebody up there was watching over {num}.",
		"Leave your bags. Always leave your bags.", "I'm amazed the cabin stayed in one piece.", "{injured} injured. Wishing them all a full recovery.",
		"From a crash like that, all {aboard} survived. Incredible.", "The airport fire service trains for this every week and it showed.",
	],
	"anger": [
		"Same airline, same excuses, every time.", "I want an independent inquiry, not the airline investigating itself.", "How many warnings does it take?", "They'll find a way to blame the dead pilots. Watch.", "My son works there and says morale is at rock bottom.", "Ticket prices up, standards down.", "Fire the board. All of them.", "The safety regulator should resign as well.", "Families deserve the full truth, not PR.", "I'm done flying with {airline}. Done.", "Why are we still letting airlines self-certify maintenance?", "Real people died because someone saved money.", "This should never have happened.", "Write to your representatives. Demand change.", "The press release was written by lawyers, you can tell.",
		"Pilots at {airline} have been posting about long shifts for a year.", "Somebody signed off on {reg} flying that day. I want their name.",
		"Profits over people. Every time.", "{airline} will issue a statement, a fine will be paid, nothing will change.",
		"The regulator is funded by the industry it regulates. Of course it's toothless.", "I cancelled my {airline} booking this morning.",
		"Outsourced maintenance, cheaper parts, tired crews. What did they expect?", "How is {airline} still allowed to operate?",
		"The CEO's bonus last year could have paid for a lot of safety.", "Don't tell me 'thoughts and prayers'. Tell me what went wrong.",
		"There should be criminal charges if negligence is proven.", "I'm furious. People trusted them with their lives.",
		"Bet the maintenance logs mysteriously go missing.", "Every few years it's the same story with budget carriers.",
		"The union warned about this. In writing.", "Shame on everyone who cut corners on that aircraft.",
		"Boycott {airline} until the report is out.", "They advertise cheap fares. Now we know the real price.",
		"Why did nobody ground the fleet after the last incident?", "I hope the families sue them into the ground.",
		"Accountability. That's all anyone is asking for.", "Our airports are run like shopping malls with runways.",
		"This airline treats its staff terribly and it shows.", "If this was a car company there'd be a recall tomorrow.",
	],
	"technical": [
		"That type has a very good engine-out climb performance, so a single failure doesn't explain it.", "Look at the timing of the last ATC call. They were busy.", "A go-around in that situation needs full thrust immediately.", "Check whether the autothrottle was engaged.", "Approach speed looks about 20 knots high in the data.", "Glide path deviation alerts would have been triggered.", "Inspectors will look at the elevator trim position first.", "Night, rain and a black-hole approach: a classic trap.", "Wake turbulence from a heavy ahead? Worth checking the spacing.", "The flap asymmetry protection on that type is good, unlikely culprit.", "Low-level windshear could explain the sudden sink.", "Maintenance records for the engines will be pulled tonight.", "Dual hydraulic failure would make the gear and flaps hard work.", "Checklist discipline is drilled into crews for exactly this.", "Notice how quickly the fire took hold: fuel tanks breached on impact.",
		"The {short} has a stick shaker and a stall warning. Something stopped them reacting, or they never got the chance.",
		"Look at the descent rate in the last minute. That's not a controlled approach.", "Mode confusion on the autopilot has caused accidents before.",
		"If the flaps weren't set right, the stall speed changes a lot.", "Final report will take a year, but the FDR is the key.",
		"The {type} can glide a long way. Where they ended up says a lot.", "Was there a go-around attempt? The track suggests not.",
		"Unstable approaches should end in a go-around. Every airline trains that.", "{wx_hard} at that airport is challenging but well within limits.",
		"CVR will tell us what the crew were thinking. FDR tells us what the aircraft was doing.", "Check the ATC tapes. Was there a late runway change?",
		"Hydraulic failure on that type would leave them with manual reversion. Heavy, but flyable.", "I'd want to know the weight and balance sheet.",
		"Both engines? Unlikely. One engine? Survivable. So what else happened?", "Spatial disorientation at night over water is a real killer.",
		"The angle of the wreckage suggests a high nose-down attitude at impact.", "Fuel exhaustion is easy to rule out: was there fire? There was.",
		"Ground proximity warnings would have been screaming in that cockpit.", "Crew resource management breaks down under stress. That's human.",
		"An aircraft this young shouldn't have fatigue issues.", "Bird ingestion on both engines is rare but not impossible.",
		"Icing conditions? I'd check the temperature at that altitude.", "Windshear alerts are mandatory on that type. Did it trigger?",
		"The investigators will rebuild the aircraft in a hangar. They'll find it.", "Speculation helps nobody, but the data so far points at the approach phase.",
	],
	"pilot": [
		"We had a minute's silence in the crew room this morning.", "Sim checks next month will be tough, as they should be.", "Every one of us has had a day where things stack up.", "Please support the crew's families too. They're grieving.", "Talk to your pilot friends today. They'll need it.", "Training saves lives, but it can't save every life.", "Professionalism isn't perfection. It's how you handle the bad days.", "The cockpit is not a place for blame. That's what investigations are for.", "I flew past that airport last night. Eerie.", "Proud of the cabin crew, whatever happened up front.", "The flight deck door was the last thing those pilots saw. Respect.", "We'll all fly a little more carefully tomorrow.", "Instructors everywhere will be teaching this one.", "Safety is everyone's job, from ramp to cockpit.", "Fly the aircraft first. Always.",
		"Twenty years flying and you never stop training for the worst day.", "We all know a crew could be us. Be kind.",
		"Every pilot reading this is checking their own habits tonight.", "Please don't judge the crew from a phone video.",
		"Cockpits are calm places until they aren't. Nobody here knows what they faced.", "Pilots want answers more than anyone. Let the investigators work.",
		"Fly safe, colleagues. Check each other.", "I knew someone who flew with {pilot}. A careful, kind person.",
		"The first officer's job is to speak up. The captain's job is to listen. Training covers both.", "Accidents are almost never one person's fault.",
		"We fly with two engines, two crew and two of everything for a reason.", "Our simulator sessions next month will include this scenario, guaranteed.",
		"If you're a nervous flyer reading this: we train for this every six months.", "Respect to the crew of {num}. Whatever happened, they were fighting it.",
		"Pilot fatigue is real. Rosters need fixing industry-wide.", "From the flight deck: thoughts with everyone at {airline}.",
		"Armchair captains, please sit this one out.", "It's a lonely job when something goes wrong at 200 feet.",
		"I'll fly the same route tomorrow. With extra care.", "Safety culture means reporting mistakes without fear. Hope {airline} has one.",
		"The best pilots I know are the most humble ones.", "Nobody goes to work wanting to crash an aeroplane.",
	],
	"misinfo": [
		"The real death toll is being hidden, my friend's cousin told me.", "Funny how the black boxes always 'need more time'.",
		"There was a second plane. People saw it. Why is nobody talking about it?", "The pilot was on his phone, I read it somewhere.",
		"Government test gone wrong. Watch them blame the weather.", "They're going to blame the dead pilot because he can't defend himself.",
		"This is the third one this year they've covered up.", "That airport's radar has been broken for months, everyone knows.",
		"Solar flares. Look up what happened to the satellites that day.", "The {short} was secretly grounded in other countries.",
		"Insurance fraud. The plane was worth more crashed.", "They paid the witnesses to change their stories.",
		"The airline knew and flew anyway. I have proof but they'll delete it.", "Weather was perfect, so it must have been sabotage.",
		"Ask yourself why the media all use the same words.", "I saw a flash in the sky before it went down. Missile.",
	],
	"eyewitness": [
		"I was walking the dog near {place} and the ground shook.", "The noise was the worst part. Engines screaming, then silence.",
		"We saw the smoke from our office window and everyone went quiet.", "Neighbours were running with blankets and water bottles.",
		"My windows rattled. I thought it was thunder at first.", "I'll never forget the orange glow over the trees.",
		"I pulled over and called the emergency services. The line was already jammed.", "It came in from the {from} direction, really low.",
		"Helicopters overhead all night. Nobody slept.", "I filmed it but I'm only giving the video to investigators. Not posting it.",
		"There were farmers on tractors helping clear a path for the fire trucks.", "The smell of fuel drifted over the whole village.",
		"We heard one engine making an odd sound before it went down.", "Kids were coming out of school when it flew over.",
		"Total silence after the impact. Then the sirens started.", "I saw people walking away from the wreck. It was surreal.",
	],
	"family": [
		"My aunt was on {num}. We're at the airport waiting for news.", "My colleague's son was flying home for his birthday.",
		"My neighbour's daughter was cabin crew on that flight.", "My grandad flew that route every month. We still can't reach him.",
		"Our family friend was in seat 3C. He survived. We're so grateful.", "My best friend texted 'landing soon' and then nothing.",
		"We were supposed to meet my brother at arrivals.", "My mum was coming back from visiting my sister in {from}.",
		"Please, if anyone was on {num} and saw a woman in a red coat, message me.", "Thank you to the nurse at {place} who held my dad's hand.",
		"My husband was on board. He is alive and he is my whole world.", "We lost my cousin. She was 19 and wanted to be a pilot.",
	],
	"nervous": [
		"My therapist is going to hear about this one.", "I'll be holding my partner's hand the whole flight now.", "Does turbulence ever actually bring planes down?", "Is {airline} safe to fly with?", "I'm due to fly from {from} tomorrow. Help.", "I'll be watching the cabin crew's faces the entire time.", "Are smaller planes more dangerous?", "I wish I could just take a train to {to}.", "How long until I stop feeling sick about flying?", "Honestly thinking of driving the whole way.",
		"I have a flight booked next month and now I can't sleep.", "My kids are flying alone to their dad's next week. I'm terrified.",
		"Is it safer to sit at the back? Asking seriously.", "I've never been scared of flying until today.", "Should I cancel my trip to {to}?",
		"How do pilots stay calm doing this every day?", "I'm going to take the ferry this summer.", "I fly for work every week. This is really getting to me.",
		"Can anyone recommend a fear of flying course?", "My hands are shaking just reading the comments.", "What are the odds, honestly?",
		"I keep checking the {airline} app for my booking.", "Can someone tell me something reassuring please.",
	],
	"media": [
		"Interviewing grieving relatives at the airport is low. Give them space.", "Good to see {outlet} waiting for facts before speculating.",
		"The drone footage over the site is too much.", "Why does every channel need its own 'aviation expert'?",
		"Thank you {outlet} for the family helpline number at the top.", "The live ticker counting victims is grotesque.",
		"Please stop calling it a 'tragic accident' before we know if it was an accident.", "Respectful coverage so far, credit where due.",
		"Blurring the faces of the injured is the least they can do.", "Headline writers, please think about the families.",
	],
	"question": [
		"Wondering that too.", "Check the airport's website.", "They said more information tomorrow.", "Ask the gate staff, they usually know.",
		"Is there a list of the airlines flying the {short}?", "When is the preliminary report due?", "Does anyone know the gate the flight left from?", "How can families get information?", "Will flights from {from} be delayed tomorrow?", "Is it true the black boxes were damaged?", "Was the aircraft recently serviced?", "Who was the captain?", "Is the runway closed?", "How do investigators reconstruct a crash?",
		"Has the airline released the passenger list yet?", "How many crew were on board?", "Is there a fund for the victims' families?",
		"Which hospital are the survivors in?", "Has the airport reopened?", "Who leads the investigation, the CTSB?", "Were the recorders found?",
		"Is the {short} still flying with other airlines?", "How old was the aircraft?", "Will there be a memorial service?",
		"Can volunteers help at the site?", "Was the weather a factor?", "Did ATC report anything unusual?",
	],
	"praise": [
		"Absolute professionals from start to finish.", "The captain walked through the cabin afterwards checking on everyone.", "I've flown for 30 years and never seen crew handle it better.", "Proud of our aviation people today.", "The airport fire crew were superb.", "Calm voice on the PA, firm instructions, everyone safe.", "Five stars to the whole crew.", "They deserve a parade.", "That's what professionalism looks like.", "Thank you for getting us home.",
		"The captain's announcement was calm and clear. Thank you.", "Cabin crew handed out water to everyone stuck on the apron.",
		"Ground staff at {to} sorted everyone's rebooking within an hour.", "Hats off to the crew of {num}.", "That landing was smoother than most normal ones.",
		"{airline} handled this professionally.", "The pilots came out to talk to passengers afterwards. Class.", "Five stars for the crew, zero for my nerves.",
		"Training paid off for everyone today.", "The crew's calm made everyone else calm.", "Brilliant airmanship.",
	],
	"relief": [
		"Good news for once.", "Nothing dramatic, just good flying.", "Turning back is always the right call when unsure.", "Everyone home safe, nothing else matters.", "Love a happy ending.", "A precaution, nothing more.", "Well handled all round.", "Grateful it was nothing serious.", "Short delay, long life.", "That's aviation safety working.",
		"Phew. Glad that ended well.", "Better safe than sorry. Every time.", "Good call by the crew to turn back.", "No harm done, that's what counts.",
		"Exactly how it's supposed to work.", "A non-event, handled perfectly.", "The system worked. Nobody hurt.", "Relieved for everyone on board.",
		"A boring ending is the best ending.", "Scary for a minute, fine in the end.",
	],
	"joke": [
		"My lunch also returned to the airport.", "Next time the bird should buy a ticket.", "I'd have stayed on board for another lap.", "That's the most excitement {from} has seen all year.", "Captain wanted to show off the new paint job one more time.", "The engine didn't like the seafood either.", "Bonus miles for the scenic route.", "Ten out of ten, would land twice again.", "The goose has filed a complaint.", "Return to sender.",
		"The bird booked an economy ticket and got upgraded to engine class.", "Extra free sightseeing loop, thanks {airline}!",
		"Plot twist: the pilot just wanted another go at the landing.", "Somewhere a goose is telling its friends it took down a {short}.",
		"Still more legroom than my last flight.", "At least the coffee was hot.", "I'd have demanded a second packet of peanuts.",
		"My luggage probably went to {to} without me.", "The seatbelt sign finally got respect.", "Five-star turbulence, would not recommend.",
		"This is why I always pick the aisle seat. Easier to run.", "Free roller coaster with every ticket.", "That's one way to skip the queue at {from}.",
	],
	"complaint": [
		"The voucher won't even cover a sandwich at {from}.", "Still no refund three weeks later.", "Customer service hung up on me twice.", "The queue at the transfer desk was two hours.", "Our connection left without us.", "Nobody spoke English or Calderran at the help desk.", "We got different answers from every staff member.", "My kids slept on our coats at the gate.", "The airline app said 'on time' the whole evening.", "Bags arrived a day later, soaking wet.",
		"Four hours at the gate and one bottle of water.", "Nobody from the airline answered the phone.", "My compensation claim was rejected. Of course.",
		"The rebooking app crashed every five minutes.", "We slept on the floor at {to}.", "Missed my sister's wedding because of this.",
		"They lost my bag on top of everything else.", "The hotel voucher was for a place an hour away.", "Zero updates for three hours.",
		"Staff were lovely, management is useless.", "The airport had no food open after midnight.",
	],
	"weather": [
		"The radar picture over {to} looked like a war zone.", "Hail the size of marbles at the terminal.", "Our pilot found a gap and slipped through. Legend.", "Fog so thick you couldn't see the tail from the cockpit, I bet.", "Winds gusting forty knots at the field.", "Everyone diverting to the same airport, chaos.", "Snowploughs out on the runway in June? Wild.", "The storm passed in an hour but the backlog took all night.", "Glad the crews didn't push it.", "Thunder rattled the windows of the departure hall.",
		"Lightning lit up the whole apron. Spectacular and terrifying.", "Ninety minutes of holding. I know every cloud by name now.",
		"Pilots aren't paid to be brave, they're paid to be careful.", "Diverted to {to}, then bussed back. Long night.",
		"Storm warnings were out since lunchtime.", "Rain so heavy you couldn't see the runway lights.", "Thank you ATC for keeping everyone apart tonight.",
		"Grounded but safe. I'll take it.", "My flight landed between two cells. Bumpy but the crew nailed it.", "Forecasters called this one perfectly.",
	],
	"business": [
		"Fares under 80 on the launch week, nice.", "The route will need a bigger plane by next summer.", "Will they code-share with anyone?", "Good to see regional airports getting attention.", "Slots at {to} are gold dust, smart move.", "This takes passengers straight from the competition.", "Weekend frequencies would make it perfect.", "Corporate travel will love this route.", "The cargo hold will carry fresh fish to {to}.", "A win for {from}.",
		"Competition on this route can only be good for fares.", "{airline} needs this route to work after last year's losses.",
		"Locals have been asking for a direct service for years.", "Hope they keep the evening departure, it suits commuters.",
		"The tourism board will be thrilled.", "Another route, another price war.", "I'll try it once and see.",
		"Good for jobs at {from} airport.", "The schedule looks tight. Hope the turnarounds hold.", "Finally a reason to visit {to}.",
	],
	"general": [
		"Wild times.", "Following this story.", "Hope there's an update soon.", "Fascinating stuff.", "Didn't see that coming.", "Great reporting.", "Bookmarking this.", "Keep us posted, {outlet}.",
		"Aviation never gets boring.", "Thanks for the update.", "Interesting times for flying.", "Would love to see a follow-up on this.",
		"Saving this article.", "Good read.", "Sharing with my avgeek group.", "Something to keep an eye on.",
	],
}

## How the world answers the player's own comment: lines by the kind of thing the player said.
const TO_PLAYER := {
	"grief": [
		"I feel the same.", "Thank you for saying it.", "Hugs to you.", "So true.","Beautifully said.", "Thank you for this.", "Couldn't agree more. Thinking of them all.", "This made me tear up.", "Well put. Rest in peace to all of them.",
		"Exactly how I feel.", "Sending love your way too."],
	"blame": [
		"Let the facts come out first.", "You're not wrong.", "That's harsh but someone needs to say it.", "The report will tell.","You can't know that yet. Wait for the report.", "Agreed, someone has to answer for this.", "Easy to blame from behind a keyboard.",
		"Totally with you. Accountability now.", "Let's see what the investigators find first.", "Strong words, but fair.", "Calm down, families read these comments."],
	"praise": ["The crew really were brilliant.", "Agreed, they deserve medals.", "Totally. Calm heads saved the day.", "Couldn't have said it better.",
		"Respect to them.", "Hear hear."],
	"question": ["Good question. Nothing official yet.", "Investigators usually publish a preliminary report within a month.", "{airline} has a helpline, try that.",
		"I read it on the {outlet} live page, scroll up.", "No idea, wondering the same.", "Someone at the airport said it reopened this morning."],
	"fear": [
		"You're not alone in feeling that.", "Millions of flights land safely every year.", "The crews train for everything.","Flying is still the safest way to travel, honestly.", "You'll be fine. Talk to the crew when you board.", "Same here, but statistics are on our side.",
		"There are courses for nervous flyers, they really help.", "Deep breath. It'll be okay."],
	"joke": ["Haha", "Okay that's funny.", "Read the room maybe?", "lol", "Not the time but I laughed.", "Underrated comment."],
	"pilot": ["Thanks for keeping us safe up there.", "Respect, captain.", "Good to hear from someone in the industry.", "Fly safe!"],
	"other": [
		"Well said.", "Spot on.", "Ha, true.", "Good point.", "I second this.","Agreed.", "Interesting point.", "Never thought about it that way.", "Exactly.", "Hmm, not sure about that.", "Fair enough.", "+1", "This.",
		"Good take.", "Thanks for sharing."],
}


## Classifies what the player wrote, for picking how people answer.
static func classify(text: String) -> String:
	var t := text.to_lower()
	if t.contains("?"):
		return "question"
	for w in ["rip", "rest in peace", "sad", "condolence", "pray", "heart", "sorry", "tragic", "families"]:
		if t.contains(w):
			return "grief"
	for w in ["fault", "blame", "should", "negligen", "greed", "sue", "shame", "angry", "disgrace", "ground the"]:
		if t.contains(w):
			return "blame"
	for w in ["hero", "well done", "great job", "amazing", "brilliant", "thank", "legend"]:
		if t.contains(w):
			return "praise"
	for w in ["scared", "afraid", "nervous", "terrified", "worried", "fear"]:
		if t.contains(w):
			return "fear"
	for w in ["lol", "haha", "lmao", "joke", "funny"]:
		if t.contains(w):
			return "joke"
	for w in ["captain", "first officer", "as a pilot", "i fly", "cockpit"]:
		if t.contains(w):
			return "pilot"
	return "other"


static func count() -> int:
	var n := 0
	for k in LINES:
		n += (LINES[k] as Array).size()
	for k2 in TO_PLAYER:
		n += (TO_PLAYER[k2] as Array).size()
	return n
