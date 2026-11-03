class_name CommentBankExtra
extends RefCounted
## The second comment bank: new kinds of commenter for the new story topics (natural
## disasters, stranded travellers, the president, safety records, celebrities, feel-good
## stories, spotters, frequent flyers, locals...), more lines for the existing tones, and
## openers and sign-offs that are mixed in so the same line rarely reads the same way twice.
## Placeholders are the same as CommentBank ({airline}, {num}, {short}, {place}, {from}, {to}...).

## Tones that exist only here (CommentThreads always draws them from this bank).
const NEW_TONES := ["controller", "disaster", "stranded", "president", "safety", "celebrity", "feelgood", "spotter", "frequent_flyer", "geography",
	"conspiracy", "extreme_weather", "newtype", "airline_fan", "local", "travel_tip"]

const LINES := {
	# ------------------------------------------------------------------ new tones
	"disaster": [
		"Stay safe everyone near {place}. Buildings can be replaced, people can't.", "My whole street is out on the pavement in pyjamas. Nobody wants to go back inside.",
		"The aftershocks are almost worse than the main quake. You never know when it's over.", "Red Cross is asking for blood donors at every hospital in the region.",
		"If you're near {place} and safe, mark yourself safe so your family stops panicking.", "Huge respect to the rescue teams digging through the night.",
		"The power is still out across half the city. Charging phones off car batteries.", "Volunteers are handing out water at the stadium. Go if you can help.",
		"I felt it 200 km away. The lamp was swinging for a full minute.", "Animals knew. Every dog in the neighbourhood went crazy ten seconds before.",
		"Please check on your elderly neighbours. Many of them can't get downstairs on their own.", "The airport is closed but the cargo flights with relief supplies are still landing.",
		"Every time the news shows the city from above it looks worse.", "Our school has opened as a shelter. We have blankets and hot food.",
		"Drop, cover and hold on. They taught us that in school and it worked.", "Insurance companies are about to have a very long month.",
		"People are queuing at the airport hoping for any seat out.", "This is why building codes matter. The new towers are still standing.",
		"Sirens all night. Nobody slept.", "Thinking of everyone who lost their homes today.", "The bridge is closed, the tunnel is closed, the airport is closed. We're stuck.",
		"Pray for {place}.", "The ash is falling like grey snow on the cars here.", "You could see the eruption glowing from the plane window last night. Terrifying and beautiful.",
		"The whole sky went green before the tornado hit. I'll never forget that colour.", "Storm shelters saved lives today. If you live out there, build one.",
		"The hurricane hunters flew straight into the eye. Absolute madmen, in the best way.", "Boarded up, sandbagged, and now we wait.",
		"Category four and still people refuse to evacuate. Please leave.", "Snowed in at the airport hotel for two nights now. The bar has run out of everything.",
		"It's 46 degrees on the apron. The ground crews are heroes.", "The tarmac is literally melting. Flights are being cancelled because the planes can't lift off.",
		"Mother Nature reminding us who's really in charge.", "The army is flying in field hospitals. That tells you how bad it is.",
		"Relief flights stacked up over the city all night. Every one of them full of supplies.", "Mobile network is down. If your family hasn't called, it doesn't mean the worst.",
		"Charities are saying cash donations help most right now, not clothes.", "The fire department rescued our neighbour from the rubble. Twelve hours later. Alive.",
		"Look for the helpers. There are always helpers.", "The aftershock just now was a 5.8. Everyone ran out of the supermarket again.",
	],
	"stranded": [
		"Day two sleeping on the terminal floor. The carpet is not as soft as it looks.", "Rebooked three times. Still not going anywhere.",
		"Shout out to the gate agent who stayed calm while 300 people shouted at her.", "Hotel vouchers ran out in about four minutes.",
		"Missed my sister's wedding because of this. Can't even be angry at the weather.", "The departures board is just a wall of red CANCELLED.",
		"Pro tip: the chapel on the third floor is the quietest place to sleep.", "Queue for the rebooking desk goes all the way back to security.",
		"A stranger shared her phone charger with me and now we're best friends.", "Airline app crashed. Website crashed. Phone line says the wait is four hours.",
		"Kids are running laps around the terminal. Honestly, same.", "The duty-free sold out of chocolate. Morale is at an all-time low.",
		"Someone started a sing-along at gate 22 and it's actually lovely.", "Trying to get from {from} to {to}. Currently somewhere in between, emotionally and physically.",
		"Rented the last car in the city. Driving home. 14 hours. Wish me luck.", "Free pizza for everyone at gate B7! Faith in humanity restored.",
		"I've been here so long the cleaners know my name.", "Compensation forms are going to be a nightmare after this.",
		"They're handing out blankets and bottled water. At least it's something.", "My connection left without me, my bag left without me, I'm the only one still here.",
		"Day three update: I have learned the entire terminal map by heart.", "If you're stuck at {to} and need a sofa, message me. Locals are opening their homes.",
		"Every hotel within 50 km is full.", "The pilots are stuck here too. Saw a whole crew asleep in a row by the window.",
		"Airline just texted that my flight is delayed by 'a few hours'. It's been 31.", "Honestly the staff are doing their best. Be kind to them.",
		"Starting a petition to make airport chairs without armrests.", "Watching the snowploughs out the window like it's a sport.",
		"The tannoy keeps saying 'we apologise for any inconvenience'. Any??", "Somebody brought a guitar. This is now a festival.",
	],
	"president": [
		"Say what you like about politics, the crew who fly the president are the best of the best.", "Two fighter jets on the wingtips. Now that's an escort.",
		"Never seen security like this at the airport. Snipers on the terminal roof.", "Calderra One looked stunning on the approach today.",
		"Whatever your politics, today is a terrible day for the whole country.", "The pilots of the state flight train for years. This should never have happened.",
		"There will be documentaries about this day for the rest of our lives.", "Imagine being the pilot. The weight of the whole nation in the left seat.",
		"Flags at half mast on every building in town.", "My grandfather said the same thing happened in his time. History repeating.",
		"Everyone will remember exactly where they were when they heard.", "Conspiracy theories in 3, 2, 1...",
		"The escort pilots must be devastated.", "Why was the president flying in that weather at all?",
		"Parliament has been recalled. This is serious.", "The state funeral will be the biggest event this country has ever seen.",
		"Respect to the presidential flight crew. They did their job today and brought everyone home.", "Saw the fighters break off and come back. Gave me chills.",
		"Somebody in that squadron is getting a medal.", "The whole world is watching Calderra tonight.",
		"I don't even like the president but I'm in tears.", "This will change how the state flight operates forever.",
		"The flypast at the airport was incredible. Two jets and the big Skyliner.", "My kids waved at Calderra One from the beach. The pilot rocked the wings!",
		"Imagine your job is 'fly the head of state and don't hit the fighter jets'.", "There should be a full public inquiry. No cover-ups.",
	],
	"safety": [
		"There's a reason the cheap airlines are cheap.", "Every airline says safety is their top priority. The data says otherwise.",
		"One star out of five and they still sell out every flight. People only care about the price.", "I flew {airline} last month. The cabin looked tired, I'll admit that.",
		"Safety ratings should be printed on the boarding pass.", "The regulator needs to stop warning and start grounding.",
		"Flying is still safer than driving to the airport, even on the worst-rated airline.", "Pilot friends of mine refuse to work for some of these carriers.",
		"Short rest periods, tight turnarounds, pressure to fly in bad weather. That's how accidents happen.", "Five stars and never had an accident. Pay the extra fifty.",
		"Unions have been warning about this for years.", "I'll take the delay if it means they actually fix the plane.",
		"Ratings are based on standards, not luck. Good airlines make their own luck.", "Island airports are the hardest in the world. That airline's numbers make sense.",
		"Their maintenance base was in the news last year. Nothing changed.", "Will be checking the ratings before booking from now on.",
		"Training is the difference. Simulator hours aren't cheap.", "Respect to the airlines that publish their safety data openly.",
		"My dad flew for {airline} for thirty years. Never cut a corner.", "Low-cost doesn't have to mean low safety. Some of them are excellent.",
		"Anyone else check the aircraft registration before boarding now?", "League tables like this push airlines to do better. Good journalism.",
		"Show me the training budget and I'll tell you the safety record.", "The best airlines have a culture where anyone can speak up. Even the newest cabin crew.",
	],
	"celebrity": [
		"She was so lovely to everyone in the cabin. Signed autographs for half the plane.", "Imagine boarding and seeing HIM in seat 2A.",
		"Of course they flew business. Must be nice.", "The crew deserve a medal for keeping the selfie queue under control.",
		"Fans were waiting at arrivals at 3am with banners.", "I sat two rows behind and didn't even recognise them in sunglasses.",
		"Apparently they tipped every member of the crew. Class act.", "Celebrities on commercial flights is my favourite genre of news.",
		"The paparazzi at the gate were worse than the turbulence.", "He ordered the chicken. He's just like us.",
		"Why is this news? Let people fly in peace.", "My cousin is a flight attendant and says the famous ones are usually the nicest.",
		"Private jet broke down so they flew with us normal people. Legend.", "The captain made an announcement welcoming them and the whole plane cheered.",
		"Can't believe my flight was the boring one with no celebrities again.", "They posted a selfie with the pilots. The pilots look starstruck.",
		"A proposal AND a celebrity on the same flight? Somebody make a film.", "The baby born on board should get free flights for life.",
		"Born at 37,000 feet. What a story to tell at school.", "Airlines usually give the baby free flights forever. I hope this one does too.",
		"She said YES! The whole cabin clapping is the best thing on the internet today.", "Proposing on a plane is high risk. Nowhere to run if she says no.",
	],
	"feelgood": [
		"Finally some good news on this site.", "This made my whole week.", "I'm not crying, you're crying.", "The world needs more stories like this.",
		"Crew who go above and beyond deserve recognition.", "Saving this for the next time I need cheering up.", "The comments are wholesome for once. Keep it up everyone.",
		"Imagine being the kid who got to sit in the cockpit after landing.", "That airport dog deserves a promotion.", "The lost teddy bear came home! Best news of the year.",
		"Retirement flight with a water cannon salute. Goosebumps.", "Forty years of flying and never missed a day. Respect, Captain.",
		"The whole terminal applauded when the soldiers walked through arrivals.", "A pilot who reads bedtime stories over the PA. We don't deserve this.",
		"Brought my grandmother to see the planes for her 90th. She talked about it for weeks.", "Small acts of kindness at 35,000 feet.",
		"Somebody give that gate agent a raise.", "The ground crew waving goodbye to every departure is my favourite thing about this airport.",
		"Faith in humanity: restored.", "My kids want to be pilots now. Thanks a lot.", "Proof that the airline industry still has a heart.",
		"This is the content I'm here for.", "The first flight of the new {short} was beautiful to watch.", "Wholesome aviation news is the best aviation news.",
		"Tell me this isn't going to be a film in two years.", "I've read this three times now. Still smiling.",
	],
	"spotter": [
		"Caught that landing from the fence. Absolute butter. Pictures on my profile.", "Look at the vapour off the flaps on that approach. Perfect light.",
		"Rare livery alert! First time I've seen that one here.", "The new {short} is so quiet compared to the old ones.",
		"Spotters at the end of the runway cheered when the gear touched.", "Two hours in the rain for one photo. Worth it.",
		"That crosswind landing was textbook. Wing down, rudder, straight.", "Golden hour at {to} is unbeatable for photos.",
		"Shout out to the airport for building a proper viewing area. More airports should do this.", "Got the registration on video. {reg} for the logbook.",
		"The go-around was even better than the landing. Full thrust right over our heads.", "That paint scheme looks even better in real life.",
		"Plane spotting is basically birdwatching for people who like jet fuel.", "My camera lens is longer than my arm and I regret nothing.",
		"Heavy rain plus landing lights equals the best photos of the year.", "The double-decker on short final looks like it's barely moving.",
		"Air traffic control audio plus a long lens. Perfect Saturday.", "Any spotters going to the airshow at the weekend?",
		"Smoke off the mains, reversers roaring. This is my therapy.", "The fighters and the presidential jet in one frame. I can retire now.",
		"Kids at the fence lost their minds when the pilot waved from the cockpit.", "Wingtip vortices in the fog. Absolutely magical.",
	],
	"frequent_flyer": [
		"Two million miles and I still get excited at takeoff.", "Aisle seat, noise-cancelling headphones, no checked bags. That's the secret.",
		"The lounge at {from} is the best I've been to. Fight me.", "I fly this route every week. The crew know my coffee order.",
		"Status match season is the most important time of the year.", "Always pack a spare shirt in your cabin bag. Learned that the hard way.",
		"Sat next to a nervous flyer today and talked her through the whole flight. She was fine.", "Upgraded to business for the first time in a year. I'm a new person.",
		"Pro tip: the first row of economy has the most legroom on the {short}.", "Missed my connection by four minutes. The jog of shame.",
		"Window seat for the takeoff, aisle seat for everything else. Choose wisely.", "My kids have more passport stamps than I did at 30.",
		"The red-eye is a lifestyle, not a flight.", "Airline food has genuinely got better. Don't @ me.",
		"I can tell the aircraft type from the sound of the engines now. Is that a problem?", "Nothing beats a perfectly smooth landing after a long-haul.",
		"Gate change, gate change, gate change. The classic.", "Lost luggage twice this year. I now travel with two pairs of socks in my pockets.",
	],
	"geography": [
		"Fun fact: {to} is further north than most people think.", "Flying over the Rockies on a clear day is the most beautiful thing.",
		"The view of the Alps on the approach to Zurich is unreal.", "Most people don't realise how close Copenhagen is to Sweden.",
		"Iceland from the air looks like another planet.", "That's the same latitude as Moscow, by the way.", "The Thames looks tiny from 10,000 feet.",
		"Las Vegas at night from the air is like a jewellery box spilled in the desert.", "Seeing the Statue of Liberty from the window on approach never gets old.",
		"Oslo in winter at 3pm is already pitch dark. Wild.", "The fjords from above make every flight to Norway worth it.",
		"New Orleans is basically surrounded by water on all sides.", "Denver is a mile up. Planes need longer runways there because of the thin air.",
		"The Canaries are closer to Africa than to Spain.", "From the plane you can see where the Gulf Stream meets the cold water.",
		"Greenland is mostly ice, three kilometres thick in the middle.", "Fun fact: Atlanta is the busiest airport on Earth by passengers.",
		"The Danube flows through four capital cities. Vienna is one of them.", "Flying into Lisbon you go right over the old town rooftops.",
	],
	"conspiracy": [
		"Funny how this always happens right before an election.", "Nobody is asking why the radar data hasn't been released.",
		"Weather manipulation is real, look it up.", "They'll blame the pilot, they always blame the pilot.",
		"Earthquake machines are a thing. Do your research.", "Why were there so many planes in the sky that day? Think about it.",
		"The official story doesn't add up. Just saying.", "Ask yourself who benefits.",
		"Chemtrails. Look at the sky. Wake up.", "The real reason the airport closed will never come out.",
	],
	"extreme_weather": [
		"That tornado crossed the interstate right in front of us. I've never driven so fast.", "Hail the size of golf balls. Every car in the car park has dents.",
		"Lightning hit our plane on climb out. Big bang, flash, then the pilot calmly said 'that was lightning, we're fine'.", "The ash cloud is moving east. Europe's airspace could close tomorrow.",
		"Whiteout. Couldn't see the end of the jet bridge.", "Planes can't take off when it's this hot. Physics doesn't care about your holiday.",
		"The hurricane flattened the hangar but the planes were flown out in time.", "Tornado sirens in the terminal. Everyone was sent to the basement.",
		"Ice on the wings, de-icing trucks everywhere. Two-hour delay but I'll take it.", "Volcanic ash melts inside the engines and turns to glass. That's why they close the sky.",
		"Microburst on final. The pilot went around and the whole plane cheered.", "My kids slept through the whole hailstorm. I did not.",
		"Storm chasers on the highway outnumber the normal drivers today.", "Heatwave rule: the earliest flight of the day is your friend.",
		"Snowploughs in formation on the runway are oddly satisfying.", "Lightning hits every airliner about once a year. They're built for it.",
	],
	"newtype": [
		"The new {short} is a beauty. Those wingtips!", "First flight on the {short} today. The cabin is so quiet.",
		"Bigger windows, higher humidity, less jet lag. The new generation really is better.", "The twin-engine jumbo is going to change long haul completely.",
		"Turboprops are making a comeback and I'm here for it.", "Split wingtips save something like four percent fuel. Engineering is cool.",
		"Saw the new widebody on its test flight. Enormous.", "The {maker} order book must be bursting after this.",
		"Can't wait to fly in it. Booking a route just to try it.", "Those engines are the size of a narrow-body fuselage. Insane.",
		"Ultra-long-range business jets are getting ridiculous. New York to Tokyo nonstop.", "As a pilot, I'd give anything for a type rating on that.",
	],
	"airline_fan": [
		"{airline} has the best crews in the business. Always smiling.", "The new {airline} livery is gorgeous.",
		"Loyal {airline} flyer for 15 years. Never let me down.", "Their business class seat is the best I've tried.",
		"I'd fly {airline} even if it was twice the price.", "{airline} handled the delays better than anyone. Free food, constant updates.",
		"The safety demo on {airline} is actually entertaining.", "Booked {airline} purely because of the plane they use on the route.",
		"Their pilots always give the best announcements. Funny and informative.", "Every time I see that tail at an airport it feels like home.",
	],
	"local": [
		"We live under the approach path. You get used to the noise, honestly.", "The airport is the biggest employer in town. Half my family works there.",
		"Best burger in the city is at the diner by the runway fence.", "Traffic around the airport is a nightmare this week.",
		"The new terminal looks amazing at night.", "When the wind is from the west the planes come right over the school.",
		"Living near the airport means free airshows every day.", "We moved here for the jobs at the airport and never left.",
		"The car park prices are a scandal. Take the train.", "Lots of locals came out to watch the first flight of the new route.",
		"Our town wouldn't exist without that airport.", "My grandad helped build the original runway.",
	],
	"travel_tip": [
		"Download your boarding pass before you get to the airport. The Wi-Fi here is useless.", "Book the first flight of the day. It's the least likely to be delayed.",
		"Always check the safety rating before booking. It takes ten seconds.", "Travel insurance is not optional in hurricane season.",
		"Pack medication in your hand luggage. Always.", "If your flight is cancelled, call the airline while you queue at the desk. Whoever answers first wins.",
		"Turbulence is uncomfortable, not dangerous. Keep your seatbelt on and you're fine.", "Want a smooth ride? Sit over the wing.",
		"Winter travel tip: leave a full day buffer before anything important.", "Stay hydrated on long-haul. Your skin and your jet lag will thank you.",
		"Volcanic ash closures can last days. Have a plan B if you're flying around Iceland.", "Earthquake zones: the safest place in an airport is away from the big windows.",
	],
	"controller": [
		"Retired controller here. Forty aircraft an hour on one runway, and you're only as good as your last clearance.",
		"Controllers are human. Understaffed, overworked, and still the reason flying is so safe.", "This is why pilots look out of the window even when they've been cleared.",
		"Runway incursions are the scariest thing in aviation. Glad this one ended well.", "Every tower should have ground radar. No excuses.",
		"The pilots caught it. That's how the system is supposed to work - layers of safety.", "I'd love to see the tower tapes from this.",
		"Imagine juggling ten jets in fog with half the staff off sick.", "Give the controllers more breaks and fewer double shifts.",
		"My cousin works in the tower at {to}. Most stressful job she's ever had.", "Line up and wait has caused more near misses than people realise.",
		"The read-back is there for a reason. Always question a clearance that doesn't feel right.", "Hats off to whoever ran that tower during rush hour.",
		"The tower view at night must be incredible though.", "Controller of the year material right there.", "I tried the tower simulator once. Lasted four minutes.",
		"Clear to land, clear for takeoff, same runway. Somebody's having a very bad day.", "Unions have been warning about controller staffing for years.",
	],
	# ------------------------------------------------------------------ more lines for existing tones
	"condolence": [
		"My heart goes out to everyone who was waiting at arrivals.", "Sending love to the families of everyone on {num}.", "No words. Just sadness.",
		"Hold your loved ones a little tighter tonight.", "To the crew who did everything they could: thank you.", "The whole aviation community is grieving.",
		"May the families find comfort in each other.", "Lit a candle at the airport chapel this morning.", "Such a heavy day. Rest in peace to all aboard.",
		"I hope the survivors heal, body and mind.", "Every life on that plane was someone's whole world.", "Thinking of the rescue workers too.",
		"The silence at the airport today said everything.", "Can't stop thinking about the families.", "Fly high, crew of {num}.",
		"From all of us in {to}: we stand with you.", "There are no words for this kind of loss.", "Strength to everyone affected.",
		"The empty gate at {to} is the saddest thing I've ever seen.", "Their names will be remembered.",
	],
	"anger": [
		"Somebody has to be held responsible.", "This was preventable. Mark my words.", "How many times does this have to happen?",
		"Shareholders before passengers. Every time.", "The regulator has blood on its hands.", "I want the full report, unredacted.",
		"Why was that plane even allowed to fly?", "Stop with the 'thoughts and prayers' and start with the inspections.",
		"Absolutely furious. Those people deserved better.", "No more excuses. Ground them until we know.", "Pilots overworked, planes overused. Here's the result.",
		"Someone signed off on that aircraft. I want their name.", "Accountability. That's all the families want.",
		"They cut maintenance budgets and now look.", "The airline's statement is pure PR. Disgusting.",
	],
	"technical": [
		"From the track it looks like the descent rate was way too high on short final.", "Speed decayed in the last minute. Classic energy management problem.",
		"The {short} has very good stall protection. Something else must have happened.", "Wind shear on that approach was reported by two aircraft before.",
		"Look at the ground track. The aircraft was well left of the centreline.", "The flight data recorder will tell the whole story.",
		"Crosswind at the limit for the type, plus gusts. That's a hard day at work.", "Icing conditions were forecast at that level.",
		"An unstabilised approach should be a go-around, every time.", "The debris field is long, which suggests a shallow, fast impact.",
		"If the engines were running at impact the fan blades will show it.", "This is why we have sterile cockpit rules below 10,000 feet.",
		"The CVR is going to be hard to listen to.", "Hydraulic failures on that type are rare but not unheard of.",
		"Microbursts are the most dangerous thing on approach. Can't see them coming.", ],
	"pilot": [
		"As a captain: we train for this every six months in the simulator. It's still terrifying in real life.", "Every pilot reading this is replaying the scenario in their head.",
		"Please don't judge the crew until the report is out. We all make decisions with incomplete information.", "Fatigue is the silent killer in our industry.",
		"Flew that route for years. The approach is tricky in a westerly.", "We're human. The system is supposed to catch our mistakes.",
		"Hand-flying skills matter. Automation can't save you every time.", "My thoughts to the crew's families. We're a small community.",
		"I've been in hail once. Sounded like gravel thrown at a tin roof. Never again.", "Lost both generators once in a lightning strike. Training kicked in. Landed fine.",
		"Ash encounters are every pilot's nightmare. You lose everything and you don't know why.", "Flying in formation with fighters is stressful even for the best of us.",
	],
	"nervous": [
		"I have a flight tomorrow and I'm shaking reading this.", "This is exactly why I take the train.", "My anxiety is through the roof.",
		"I'm supposed to fly to {to} next week. Should I cancel?", "Stories like this are why I can't fly without a glass of wine.",
		"Reading the comments from pilots is actually helping. Thank you.", "I'm terrified of turbulence and now this.", "Booked a nervous flyer course after reading this.",
		"Never flying in winter again.", "Is it safer to sit at the front or the back? Asking for me.",
	],
	"joke": [
		"The real hero is whoever kept the coffee machine running in the terminal.", "Pilot: 'sorry folks, slight bump'. The bump:", "My luggage has more air miles than I do.",
		"At this point the seagulls have a better on-time record.", "Plot twist: the plane was fine, it was the airport that moved.",
		"Me reading the safety card for the first time ever after this.", "Airline food was the real disaster.", "Somebody check on the duty-free Toblerone.",
		"That go-around was the most expensive roller coaster in the world.",
		"New fear unlocked.", "Me and my anxiety have booked a hotel by the train station.",
	],
	"complaint": [
		"Three hours on the tarmac with no air conditioning. Unacceptable.", "They lost my bag and then lost the paperwork about my lost bag.",
		"Paid for extra legroom, got a broken seat.", "Seven euros for a bottle of water at the gate. Criminal.", "The app said on time until we were at the gate. Then: cancelled.",
		"Compensation? Good luck. I'm still waiting from last year.", "Gate changed four times. I walked eleven kilometres today.",
		"The rebooking queue was faster than the customer service line. And the queue was three hours.", "Not a single announcement for two hours.",
		"Why does every delay come with a voucher for one sandwich?",
	],
	"business": [
		"This order book is massive. Good times for the manufacturer.", "New routes mean new jobs at the airport. Good news.", "The fuel bill alone must be terrifying right now.",
		"Low-cost carriers are eating everyone's lunch.", "Expect fares to go up. They always do after news like this.",
		"Twin-engine jumbos are the future. The four-engine era is ending.", "Rheinland Air has the healthiest balance sheet in Europe.",
		"Lone Star is expanding fast. Wonder how long that lasts.", "A merger between those two would be a monopoly on half the routes.",
		"The share price jumped ten percent on the news.", "Pilot shortages are the real story nobody is talking about.",
		"Airport fees are what make your ticket expensive, not the airline.", "Nordlys flying turboprops in the Arctic is smart. Cheaper and tougher.",
	],
	"general": [
		"Good article, thanks.", "Interesting read.", "I fly this route all the time.", "The pictures in this article are amazing.", "Didn't know that. Fascinating.",
		"More stories like this please.", "Bookmarked.", "Love seeing aviation in the news for good reasons.", "This is why I love this site.",
		"Can't wait to fly again.", "Sharing this with my dad, he'll love it.", "Who else reads every aviation story on here?",
		"The new airports on the network are great.", "Atlanta to Denver on the new route was smooth as silk.", "Berlin's new airport is finally working properly.",
		"Barcelona approach over the beach is one of the best in Europe.", "Seattle in the rain with the Space Needle in the mist. Beautiful.",
		"Vegas at night from the window. Nothing like it.", "Frankfurt skyline at sunrise from the left seat. Unbeatable.", "Copenhagen's airport is so easy to get around.",
	],
	"praise": [
		"Those pilots deserve every award going.", "Absolute professionals from start to finish.", "Calm, clear, decisive. Textbook airmanship.",
		"The cabin crew are the unsung heroes.", "Give that captain a medal.", "The whole crew handled it perfectly.",
		"This is why training matters.", "Proud of our aviation community today.",
	],
	"relief": [
		"Thank goodness everyone's okay.", "Phew. Scary but everyone walked off.", "Best possible outcome.", "Shaken, not stirred, but safe.",
		"My aunt was on that flight. She's fine! Thank you crew!", "All safe. That's all that matters.", "Happy ending to a scary story.",
		"Glad they made it down.", "Relieved for everyone on board.",
	],
	"question": [
		"Does anyone know if flights from {from} are running tomorrow?", "Is the airport open again?", "Will passengers get compensation for this?",
		"How long until the runway reopens?",
		"What's the safety rating of {airline}?", "Which airlines are flying the new {short}?",
		"How often do mid-air collisions happen?", "Where can I find the preliminary report?",
	],
	"eyewitness": [
		"I was at the gate when it happened. Everyone went silent.", "Saw it from the car park. The flash was huge.",
		"We felt the ground shake from the terminal.", "I watched from my balcony. The smoke went up in seconds.",
		"Watched the whole approach from the spotters' hill. Something looked wrong from the start.",
	],
	"survived": [
		"Everyone got out. The crew are heroes.", "The evacuation was textbook. Under 90 seconds.", "A miracle. Pure and simple.",
		"Those slides saved lives today.", "Nobody died. Read that again.", "The fire crews were there in two minutes. Amazing response.",
	],
	"weather": [
		"Worst storm I've seen at the airport in years.", "The wind was so strong the jet bridges were swaying.", "Planes queuing to land in the gusts. Great to watch, awful to be on.",
		"Diverted twice before we finally landed. Applause on touchdown.", "The fog was so thick you couldn't see the tail from the gate.",
		"Snow on the runway, de-icing queue round the block.", "That crosswind was something else today.", "Lightning show over the runway all evening.",
	],
}

## Openers and sign-offs mixed into lines now and then.
const OPENERS := ["Honestly,", "Not gonna lie,", "Just saying:", "Okay so", "Real talk:", "Hot take:", "As someone who flies a lot,", "Wow.", "Unpopular opinion:",
	"I'll be honest,", "Long-time reader here.", "First comment ever, but", "Can we talk about this?", "Look,", "Listen,", "Fun fact:", "Genuinely,",
	"Update:", "Same as last time:", "Speaking from experience,", "My two cents:", "Agreed with everyone above.", "Reading this from the departure lounge.",
	"Reading this on my phone at the gate.", "From {to}:", "Greetings from {from}.", "Wild.", "Oof.", "Well.", "Hmm.", "Okay, wow.", "PSA:", "Heads up:",
	"Not an expert but", "As an ex flight attendant,", "As a nervous flyer,", "As a local,", "My dad is a pilot and", "Seriously though,", "Quick thought:",
	"I keep coming back to this story.", "Can't believe it.", "Big if true.", "Plot twist:", "Story time:", "Honest question:", "Respectfully,", "Ngl,",
	"Lol.", "Imagine this:", "Calling it now:", "For the record,", "Just landed and saw this.", "Thread:", "Never thought I'd say this but", "Again?",
	"Breaking my silence on this:", "Gotta say,", "Can confirm.", "Second this."]
const CLOSERS := ["Just my opinion.", "Fly safe everyone.", "Blue skies.", "Stay safe out there.", "Thoughts?", "Change my mind.", "That's all.",
	"Rant over.", "Anyway.", "Respect.", "Wild times.", "Unreal.", "#avgeek", "#aviation", "#flying", "#travel", "#{airline}", "Mark my words.",
	"Prove me wrong.", "Love this community.", "See you at the fence.", "Safe travels all.", "Be kind to the crew.", "What a world.",
	"Sending love.", "Peace.", "Can't wait for the follow-up.", "Thanks for reporting this.", "Bookmarking.", "Unbelievable.", "Mad.",
	"Not okay.", "Absolutely.", "Big respect.", "Hats off.", "Cheers {outlet}.", "Let's see.", "We'll see.", "Time will tell.", "Just saying.",
	"Hope that helps.", "Lesson learned.", "Never again.", "Every time.", "Classic.", "Typical.", "Ugh.", "Wow.", "No words.", "Fingers crossed.",
	"Glad I'm not flying today.", "Book the train.", "Window seat forever.", "Seatbelts on, people.", "Keep your phone charged.", "Check the ratings.",
	"Hug your pilots.", "Tip your ground crew.", "Long live the turboprop.", "Long live the jumbo."]

## Extra ways the world answers the player's own comments (merged with CommentBank.TO_PLAYER).
const TO_PLAYER := {
	"grief": ["Thank you. Means a lot.", "Beautiful words.", "Rest easy, all of them.", "This is the comment I needed to read today.", "Exactly this.",
		"Couldn't have put it better.", "Holding everyone in my thoughts too.", "Agreed. Hug your people.", "Sending love back to you.", "So well said.",
		"Thank you for being kind in a thread full of anger.", "Liked and shared."],
	"blame": ["Fair, but the report comes first.", "Strong take. Not wrong though.", "Let's wait for the investigators before we burn anyone.",
		"Someone has to answer for it, agreed.", "I hear you, but the crew can't defend themselves yet.", "This. Accountability.", "Bit early for that, mate.",
		"Respectfully disagree. Pilots don't wake up wanting to crash.", "You're braver than me for saying it.", "Couldn't agree more."],
	"praise": ["100%. The crew were incredible.", "Medals for all of them.", "Truly professional.", "Pilots like that make me trust flying again.",
		"Hear hear!", "Thank you for recognising them.", "Agreed, give them a raise.", "Such class under pressure."],
	"question": ["Last I heard, flights resume tomorrow morning.", "The airline posted an update an hour ago, check their page.", "Not sure. Following for answers.",
		"Investigators usually take about a month for the first report.", "The airport website has a live board.", "Good question, wondering too.",
		"Someone in the other thread said yes.", "Ask at the transfer desk, they know more than the app.", "The regulator publishes ratings online.",
		"Usually yes, you can claim compensation."],
	"fear": ["You've got this. Millions fly safely every day.", "Pilots train for everything, honestly.", "Sit over the wing, it's the smoothest ride.",
		"Breathing exercises help me a lot.", "The crew are always calm for a reason. They know it's safe.", "I used to be terrified too. It gets better.",
		"Talk to the cabin crew when you board, they're lovely with nervous flyers.", "Statistically you're safer up there than in your car.",
		"Noise-cancelling headphones and a good film. Works every time."],
	"joke": ["Haha, dead.", "Dead.", "Stop it, I can't breathe.", "Comment of the day.", "This made me snort.", "Okay that's good.", "Too soon... but funny.",
		"Take my like.", "Underrated.", "LOL", "Somebody frame this comment."],
	"pilot": ["Respect, captain.", "Thank you for your service up there.", "Always good to hear from the flight deck.", "Fly safe, captain!",
		"Love when real pilots join the thread.", "Thanks for the insight.", "What type do you fly?", "This is why I trust pilots."],
	"other": ["Good point.", "True.", "Fair.", "Interesting.", "Agree.", "Ha, love it.", "Nice one.", "Never thought of it like that.",
		"This is the way.", "So true.", "Facts.", "Yep.", "Well said.", "Totally.", "Big agree.", "Exactly what I was thinking.",
		"Same.", "Good shout.", "Not wrong.", "This deserves more likes."],
}

## Reply tones for the new comment tones.
const REPLIES := {
	"controller": ["agree", "thanks_pilot", "pushback"], "disaster": ["amen", "reassure", "agree"], "stranded": ["complaint_reply", "agree", "lol"], "president": ["agree", "defend", "agree_anger"],
	"safety": ["agree", "defend", "airline"], "celebrity": ["lol", "agree"], "feelgood": ["agree", "amen", "lol"], "spotter": ["agree", "tech_more", "lol"],
	"frequent_flyer": ["agree", "lol", "complaint_reply"], "geography": ["agree", "correction"], "conspiracy": ["correction", "correction", "double_down"],
	"extreme_weather": ["agree", "reassure", "lol"], "newtype": ["agree", "tech_more"], "airline_fan": ["agree", "lol", "complaint_reply"],
	"local": ["agree", "lol"], "travel_tip": ["agree", "agree", "lol"],
}

## Thread moods for the new story topics and how often each tone appears in them.
const MIX := {
	"atc": {"controller": 45, "pilot": 12, "technical": 12, "anger": 8, "nervous": 8, "frequent_flyer": 7, "joke": 4, "question": 4},
	"disaster": {"disaster": 34, "stranded": 14, "extreme_weather": 12, "question": 10, "nervous": 6, "travel_tip": 6, "local": 8, "conspiracy": 3, "joke": 3, "relief": 4},
	"president": {"president": 45, "technical": 10, "anger": 10, "conspiracy": 8, "condolence": 10, "pilot": 7, "joke": 3, "question": 7},
	"safety": {"safety": 45, "anger": 12, "frequent_flyer": 10, "pilot": 8, "airline_fan": 8, "travel_tip": 7, "question": 10},
	"celebrity": {"celebrity": 50, "joke": 15, "feelgood": 15, "frequent_flyer": 10, "complaint": 5, "general": 5},
	"feelgood": {"feelgood": 50, "general": 12, "local": 8, "airline_fan": 10, "joke": 8, "spotter": 6, "frequent_flyer": 6},
	"spotter": {"spotter": 50, "newtype": 12, "general": 12, "geography": 8, "airline_fan": 8, "joke": 5, "local": 5},
	"newtype": {"newtype": 40, "business": 15, "spotter": 15, "frequent_flyer": 10, "technical": 10, "general": 10},
	"travel": {"frequent_flyer": 30, "travel_tip": 20, "stranded": 15, "complaint": 12, "geography": 10, "joke": 8, "general": 5},
}

## Templates written about a specific city, airline or aircraft type: filled from the game's own
## data, they add hundreds more distinct comments ({c} = city, {a} = airline, {t} = type).
const CITY_TEMPLATES := ["Nothing beats the view of {c} on the approach.", "Flew into {c} last spring. Gorgeous city from the air.",
	"{c} airport has the best spotting fence I know.", "Anyone else from {c} reading this?", "The taxi ride from {c} airport costs more than my flight.",
	"I'd move to {c} just for the sunsets over the runway.", "Hello from {c}! Planes overhead all day here.", "{c} at night from 10,000 feet is unreal.",
	"Weather in {c} always makes the landings interesting.", "Every time I land in {c} the whole plane claps. Every time.", "{c} has the friendliest ground crews I've met.",
	"My first ever flight was into {c}. Never forgot it.", "The new routes to {c} are a game changer.", "{c} is so underrated as a city break.",
	"Spent six hours delayed at {c} once. Know every shop by heart.", "Can confirm, the coffee at {c} airport is terrible.", "The approach into {c} is a pilot favourite.",
	"Grew up under the flight path at {c}. Miss the noise honestly.", "{c} looks like a model village from the window seat.", "Booked a weekend in {c} because of this article."]
const AIRLINE_TEMPLATES := ["Flew {a} last week. Smooth flight, lovely crew.", "{a} lost my bag in 2019 and I still haven't forgiven them.",
	"{a}'s new paint scheme is a ten out of ten.", "{a} cabin crew are always so professional.", "Their app is rubbish but {a} itself is fine.",
	"Loyal {a} customer. Never had a problem.", "{a} prices have gone up a lot this year.", "Would love to see {a} fly to more places.",
	"The {a} business class seat is a bed. A real bed.", "{a} pilots give the best announcements.", "Every {a} flight I've taken has landed early. Witchcraft.",
	"Their safety rating is the first thing I'd check before flying {a}."]
const TYPE_TEMPLATES := ["The {t} is the comfiest aircraft I've ever flown on.", "Love the sound of the {t} on takeoff.", "Pilots I know say the {t} is a dream to fly.",
	"The {t} cabin always feels so roomy.", "Saw a {t} at the fence today. Beautiful machine.", "The {t} handles crosswinds like it's on rails.",
	"Any {t} pilots here? What's it like in the gusts?", "Booked my holiday purely to fly on the {t}.", "The {t} is getting old but it's still a classic.",
	"Window seat behind the wing on the {t} is the best photo spot.", "The {t} lands so softly when it's done right.", "Would love a cockpit tour of the {t} one day."]


static func templated(r: RandomNumberGenerator, tone: String) -> String:
	## A comment about a real city, airline or type in the game.
	match tone:
		"airline_fan", "frequent_flyer", "safety":
			var codes := Airlines.all_codes()
			var a := String(Airlines.get_al(String(codes[r.randi() % codes.size()])).get("name", ""))
			return String(AIRLINE_TEMPLATES[r.randi() % AIRLINE_TEMPLATES.size()]).format({"a": a})
		"spotter", "newtype":
			var ids := AircraftTypes.all_ids()
			var t := String(AircraftTypes.get_type(String(ids[r.randi() % ids.size()])).get("name", ""))
			return String(TYPE_TEMPLATES[r.randi() % TYPE_TEMPLATES.size()]).format({"t": t})
	var aps := Airports.ORDER
	var c := String(Airports.get_ap(String(aps[r.randi() % aps.size()])).get("city", "the city"))
	return String(CITY_TEMPLATES[r.randi() % CITY_TEMPLATES.size()]).format({"c": c})


static func templated_count() -> int:
	return CITY_TEMPLATES.size() * Airports.ORDER.size() + AIRLINE_TEMPLATES.size() * Airlines.all_codes().size() + TYPE_TEMPLATES.size() * AircraftTypes.all_ids().size()


static func line(r: RandomNumberGenerator, tone: String, f: Dictionary) -> String:
	## A line for this tone, sometimes dressed up with an opener or a sign-off.
	var list: Array = LINES.get(tone, LINES.general)
	var s := NewsComments._say(r, list, f)
	if tone in ["local", "geography", "general", "spotter", "newtype", "airline_fan", "frequent_flyer"] and r.randf() < 0.3:
		s = templated(r, tone)
	if r.randf() < 0.22:
		var o := NewsComments._say(r, OPENERS, f)
		if o != "":
			# after "Honestly," or "Okay so" the line runs on in lower case; after "Wow." it starts a new sentence
			var runs_on := o.ends_with(",") or o.right(1).to_lower() != o.right(1).to_upper()
			var keep := s.begins_with("I ") or s.begins_with("I'") or s.substr(0, 1).is_valid_int() or s.begins_with("{")
			s = o + " " + (s.substr(0, 1).to_lower() + s.substr(1) if runs_on and not keep else s)
	if r.randf() < 0.2:
		var c := NewsComments._say(r, CLOSERS, f)
		if c != "":
			s += " " + c
	return s


static func count() -> int:
	## How many distinct comments this bank can produce (lines times opener/sign-off choices).
	var n := 0
	for k in LINES:
		n += (LINES[k] as Array).size()
	return n


static func combinations() -> int:
	return count() * (OPENERS.size() + 1) * (CLOSERS.size() + 1)
