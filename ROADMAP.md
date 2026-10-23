# Roadmap

## Vision

**Maison understands your home and acts for you, with nothing to set up.**

Home Assistant collects; Maison understands and acts. Going further than Home Assistant doesn't mean collecting more data than it does — it already reads thousands of brands — but doing more with that data: explaining, estimating, learning, and turning what it finds into actions.

V1 is that core, and that core only: three scores — Comfort, Energy and Network — and housekeeping, room by room, fed through one abstract source boundary that knows no brand.

## Principles

1. **The intelligence layer is the core.** Every source goes through it; no screen reads Home Assistant directly.
2. **Nothing to set up, and never a dead end.** Every feature has a path for every user: automatic when it can be, assisted otherwise (Maison suggests, one tap confirms), manual as a last resort (a form, a tap, a drawing). No "not supported", no empty screen.
3. **Manual stays smart.** What the user enters is a starting point: Maison adjusts it with what it already knows (time spent at home from the iPhone's location, weather, season, household) and recalibrates it with every real value, such as the next bill. A sensor replaces it on its own when one appears.
4. **Every number says where it comes from:** measured, estimated or entered.
5. **Local first.** The household's data stays in the home. Only what the household shares goes through iCloud: its name, the server's addresses, favourites and the plan, never a device's state or history.
6. **The best of the iPhone:** a native, polished app, and the data only the iPhone has (location, Health, weather, Focus).

## How it works

**Sources → intelligence layer → what the user sees.**

- **Home Assistant is the home's memory.** It is the always-on device that measures and keeps history, which neither the iPhone (no background work) nor HomeKit (no history) can do. Home Assistant is the only source of history for now; HomeKit and Matter will be discussed if Maison opens up to people without Home Assistant.
- **The iPhone adds what Home Assistant doesn't have:** location and presence, sleep from Health, the weather forecast, the calendar, and Focus modes. iOS only says whether a Focus is on, not which one: Maison learns "Sleep" or "Work" through a Focus filter the person adds to that Focus once (assisted). The iPhone can't list the devices on the Wi-Fi nor read what other apps play (Apple Music aside); Home Assistant brings those through the router's and the speakers' integrations.
- **Each source is a connector behind one abstract boundary, and Maison stays brand-agnostic.** Home Assistant is the first connector, not the product, and for now the only one: a box, a router or a meter reaches Maison through its Home Assistant integration, never through a connector written for that brand. Another source could later plug into the same boundary; nothing in it, and nothing V1 shows, depends on the brand behind a value.
- **Documents feed the scores, and only those.** An energy bill, an internet-box bill, an energy contract or a box contract is analysed on the device and linked to Energy or Network. A warranty, a manual, insurance or a lease waits with the inventory (see Parking).
- **What isn't connected waits.** An inventory of objects is paused, not dropped (see Parking). V1 does not ask the household to list what it owns.
- **Maison sets Home Assistant up itself:** an internet check (Ping), devices Home Assistant discovered, the energy dashboard, through the same APIs as Home Assistant's own settings. These need an administrator account; for a resident, Maison asks the administrator in one tap instead. History retention has no API (it is only set in `configuration.yaml`): the add-on sets it.
- **A Maison add-on runs the intelligence layer around the clock** on the household's Home Assistant, installed from the app in one tap (Home Assistant OS and Supervised). Home Assistant Container and Core have no add-ons: the same package ships as a Docker container to run beside it (assisted), and without either the iPhone computes the findings when the app opens and in background refreshes (manual), with fewer of them and later.
- **The only thing on our side is a push relay that stores nothing**, because the app's APNs key can't be shipped to every home. It plugs into Home Assistant the way its own app does: Maison registers a `push_url` and a push token as a mobile app, and Home Assistant's `notify.mobile_app_*` service posts to the relay, so any automation can notify through Maison. Payloads can be end-to-end encrypted.
- **Where it can, the intelligence layer is one Swift package** built for iOS and for Linux, so the add-on runs the same logic as the app. It therefore produces structured facts (a kind, values, units, the entities involved), never sentences: wording and translation happen on the iPhone, by the on-device model or the written form.

## The intelligence layer

It already exists in pieces: `DayFacts` computes the facts, `DayDigest` has them written, `GroundedNumbers` rejects a text with a number that isn't in the facts, `RuleDraft` turns a sentence into a rule. They are spread out and wired to Home Assistant: every screen reads `HomeStore.states` directly, and `DayFacts` returns translated sentences from an extension of the store. They become one module behind the source boundary, free of SwiftUI, the main actor and string catalogs, so it builds on Linux.

What it does:

1. **Unify:** one picture of the home, whatever the source, each value keeping its origin.
2. **Understand the context:** who is home, the weather, the season, the household's habits.
3. **Estimate what is missing:** from the context, how long devices ran, and the next real bill. The object inventory is paused (see Parking).
4. **Learn:** the home's usual ranges and habits; a dismissed finding or a corrected estimate counts.
5. **Explain:** always why, never a bare number.
6. **Act:** every finding ends in one tap — create a rule, launch a scene, check a device.

Its rule: **it computes, the language model only words it.** It therefore works without Apple Intelligence: when the model doesn't support the language, the findings show in a short written form instead of disappearing.

## Moments of life

Maison follows what happens in the home, not only its devices. Each moment has three levels; without any equipment, Maison's action becomes advice and reminders instead of commands. A manual entry improves the inference, and a sensor replaces the inference when it arrives.

| Moment | With a sensor | Without one (inferred) | By hand |
|---|---|---|---|
| Sleeping | Bedroom temperature, CO₂, noise | Health, Sleep Focus, usual bedtime | "Slept well?" in the morning |
| Waking up | First motion, first light | Wake-up time in Health | — |
| Showering | Bathroom humidity, water heater | Usual times, presence | One tap, a shortcut, Siri |
| Cooking | Oven or hob power, particles | Mealtimes, presence | "I'm cooking", a timer |
| Laundry | The machine's power curve | Usual times, presence | "Machine started": end reminder, cost |
| Working from home | CO₂ in the office | Weekday presence, Work Focus, calendar | "Working from home today" |
| Relaxing | TV and music in Home Assistant | Apple Music playing on the iPhone | An "Evening" scene |
| Cleaning (in V1, see below) | Robot vacuum, the room's humidity and dust | The room's type, when people are usually home, pollen, guests | Tasks per room, recurring reminders |
| Airing | Window sensors, CO₂ | Outdoor weather and air quality, season: the best time to air today | "I aired": daily reminder |
| Guests | More devices on the router (its Home Assistant integration) | Calendar | "I have guests" |
| Leaving and coming back | Locks, windows | The iPhone's location, calendar | A "Before leaving" checklist |
| Working out | — | A Health workout while at home | — |

**Inferring, then asking.** When Maison guesses ("Was that a shower?") and the user confirms, it learns; detection improves and the user has less and less to say.

**The sensor that unlocks a moment.** When a moment can't be detected, Maison can say which single sensor would do it.

**Privacy inside the household.** Everyone sees their own activity (sleep, showers); the household sees only totals ("9 showers this week"), never who did what and when. Home Assistant can't enforce this: every account reads the whole history and logbook. So what is personal stays out of it: Health data stays on the person's iPhone, and the add-on keeps per-person moments in its own store, answering each member only about themselves. A sensor's raw history stays visible to anyone with a Home Assistant account.

## Findings

What the user receives. In V1, three scores and housekeeping:

- **Comfort:** a room out of its range, heating or cooling running in an empty home, a window open while it runs.
- **Energy:** standby use, the month's projected cost, the costliest devices, use at equal weather, cheaper hours. An energy bill or the energy contract, analysed on the device, is linked to this score and recalibrates it.
- **Network:** whether the connection is up, the devices the router sees, and outages. An internet-box bill or the box contract, analysed on the device, is linked to this score.

- **Housekeeping:** what each room needs and when, after its type. Every room has a type (living room, kitchen, bedroom, bathroom, entrance, office, laundry, outdoor, other): recognised from its icon and name in the source, asked in one tap when it isn't sure, or chosen. The type gives the room's tasks and their rhythm; the room's own sensors change the rhythm (a bathroom whose humidity stays high is cleaned sooner). "Done" takes one tap, and a robot vacuum starts from Maison. Tasks belong to a room, never to an object: an object's upkeep waits with the inventory (see Parking).

After V1, still in this product: devices (offline, battery low, a frozen sensor, a device behaving unusually), safety (a door left open, unlocked after everyone left, water leak, smoke), and habits (a manual action repeated in the same context, offered as a rule). Upkeep returns with the inventory (see Parking).

Comfort ranges are never hard-coded: they are learned from the home's history or set by the user. Energy is in the currency set in Home Assistant, corrected by the next bill.

## V1

The core: the three scores, housekeeping, and the source boundary that feeds them. Brand-agnostic.

1. **Comfort, Energy, Network.** Each score keeps the origin of every value (measured, estimated or entered), says why, and ends in one tap.
2. **Housekeeping, room by room.** Every room has a type, recognised, suggested in one tap, or chosen; the type gives room-level tasks and their rhythm, and the room's sensors change it. One sheet shows the whole home for the week, each room shows its own tasks with "Done", and Rooms says what is late. Without any device it is a list of reminders that already knows each room; with a robot vacuum, Maison starts it. What was done stays on the iPhone until the add-on keeps it for the household.
3. **The source boundary.** The intelligence layer is one module behind it, with the origin of every value. Home Assistant is the first and only connector; the boundary stays generic so another source could plug in later. No screen reads a source directly.
4. **Documents, only when they feed a score.** Energy bills, internet-box bills, energy contracts, box contracts. Analysed on the device, linked to Energy or to Network.
5. **Today:** the three scores and the day summary. Each finding has its origin, its reason and a one-tap action.
6. **A useful first launch:** import Home Assistant's existing history (detailed history and long-term statistics), so Maison has something to say within minutes.
7. **Tidy the setup:** suggest rooms, hide duplicates, clear names.
8. **No dead end on a score.** Energy reads Home Assistant's energy dashboard, suggests the right meter when it isn't set, or takes a bill and a price per kWh. Comfort ranges and usual hours are learned from the history or set by the user. Network uses the router's integration when there is one.
9. **Widgets:** Home Screen, StandBy, Lock Screen. They need an App Group and a keychain access group shared with the app, so the extension can read the sign-in and refresh it.
10. **Validation, before anything paused comes back.** About five testers from outside the project, for two weeks. Success: they open the app on their own, without being reminded.

## Next

- Housekeeping signals that need a moment first: showers, cooking, working from home, guests from the calendar, pollen.
- Moments of life, starting with sleep (Health ↔ bedroom), laundry, showering, airing. Inference uses sensors, Health and what the person enters.
- Device and safety findings, beyond the three scores.
- The push relay and notifications with actions.
- The Maison add-on and the automatic Home Assistant setup.
- Estimates adjusted by presence and weather, recalibrated by real values.
- Learning from feedback; habits turned into rules.
- A floor plan without LiDAR: rooms drawn by hand, a photo of the plan to trace, or a plain list of rooms.
- Before leaving, away mode, getting the home ready for the return.
- Control Center, Siri, Shortcuts and App Intents, Focus filters.
- Week and month reviews.

## Parking

Paused, not abandoned. This waits outside V1. It comes back only after the validation above, and only when the testers use the dashboard on their own for two weeks without being reminded, and/or when they ask to store something like an appliance warranty.

- The inventory of objects, durables and consumables.
- Consumables and the replacement cycle: the median interval between replacements, and the reminders. Upkeep hangs off the same cycle (filters, descaling, smoke detector batteries).
- An emoji chosen for the object on its own.
- General documents attached to an object: warranties, manuals, insurance, leases.
- Scan from the object, scan from the home: match the object and prefill its sheet (a photo, a barcode, the QR code of the European energy label).

The Belongings code prototyped locally — models, matcher, prefill, the replacement schedule, and the tests — stays on a branch. It stays off V1.

## Later

- "Plug in the box": a ready-made Home Assistant box that Maison sets up on its own, Home Assistant invisible to the user.
- HomeKit and Matter as sources, for people without Home Assistant.
- Questions in plain language, simulations ("what if I lower it by one degree"), a year in review.
- Temporary guest access, a household feed, comfort and sleep per person.
- Live Activities, Apple Watch, iPad and Apple TV as wall dashboards, a Mac app.

## Not this product

A Maison email, a bank connection, subscriptions that don't feed a score, a condition report: that is a home-paperwork product, not this one. Energy bills, internet-box bills, and the energy and box contracts are in V1, because they feed a score. Warranties, manuals, insurance and leases wait in Parking, attached to objects.

## Gaps in the current code

Dead ends that contradict the principles above:

- The energy sensor is picked by its name (English or French words), so a sensor named in another language, or "Linky consumption", is never found (`HomeStore.energyToday`). Indoor temperature sensors are told from outdoor ones the same way, by "ext" or "out" in the name (`HomeStore.indoorTemperatureSensors`).
- The temperature ring is fixed at 10–30 °C, saturated in a hot climate and wrong in °F (`Components.swift`).
- The day summary and rule writing disappear when Apple Intelligence doesn't support the language.
- The app is in English and French only.
- A resident (not a Home Assistant administrator) gets errors where an administrator gets the rule editor, timers and door alerts, and attaching the iPhone to their person fails silently. These need a path of their own: read-only rules, and a request to the administrator.
- Nothing is cached on the iPhone: starting away from any network shows an error instead of the last known home.
- The connection isn't checked: no periodic ping, no reconnection when the app comes back to the foreground or the network changes, so a dead connection can take a long time to notice.
- Every `state_changed` event of the server reaches the app and redraws the screens; a home with power sensors updating every second will stutter. `subscribe_entities`, batched updates and precomputed lists per room are the way out.
- Commands get their id before a separate task sends them, while Home Assistant requires increasing ids: two commands sent at once could arrive out of order and be refused.
- Signing out stops the location reports, but the Maison device and its tracker stay in Home Assistant until removed there.

## Open questions

- Is sleep the heart of the product, or one moment among others?
- Wording in languages Apple Intelligence doesn't support: a simple written form only, or an optional cloud model?
- How stable are the Home Assistant APIs Maison relies on to set it up? The config entry flows, `energy/save_prefs`, the mobile app registration and its push are what Home Assistant's own frontend and apps use; onboarding (`/api/onboarding`) and installing an add-on through the Supervisor are internal and change without notice.
- What does the floor plan bring to the intelligence layer?
- Pricing: one-off purchase or subscription, given that the push relay has a running cost.
