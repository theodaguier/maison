# Roadmap

## Vision

**Maison understands your home and acts for you, with nothing to set up.**

Running a home is much more than home automation. Maison starts with what can be measured and acted on: comfort, energy and the network. What has no sensor comes in only when it serves that core, such as a bill that gives the price per kWh.

Home Assistant is the memory of everything that is measured; Maison understands and acts. Going further than Home Assistant doesn't mean collecting more data than it does — it already reads thousands of brands — but doing more with that data, and with what no sensor sees: explaining, estimating, learning, and turning what it finds into actions.

## The core

Maison is first about what is measured in the home and what Maison can act on. Each core domain has one sheet: one number with its usual range, what Maison found, and one action.

1. **Comfort:** temperature, humidity, air quality, when to air, and the bedroom at night, crossed with sleep from Health.
2. **Energy and water:** electricity, gas, water, heating, solar production, the cost of the day and the month.
3. **Network:** internet, Wi-Fi, devices on the network, outages, speed.

Control (devices, scenes, rules) and safety (doors, locks, leaks, smoke) stay the base the app already has.

## Around the core

What has no sensor comes in only when it serves the core:

- **Documents:** any document can be scanned, recognised, filed and found again. Energy bills and contracts are also read for the supplier, the price per kWh and the off-peak hours (see Reading paperwork).
- **Upkeep raised by a device:** a filter to clean, a battery running low, a device offline. No task without a device behind it.
- **Objects:** every object in the home, durable or consumable, in its room, with its emoji, its price, its warranty and its documents. Consumables (razor blades, filters, bulbs) get a replacement interval learned from the household's own replacements.
- **Presence and away mode:** for rules, such as not heating water in an empty home.

## Not now

Moments of life (sleep, showers, laundry, airing), acting on other documents (insurance renewals, lease reviews), chores and shared tasks, plants and pets, the household budget, the garden. They may come back once the core is solid; none of them gets its own tab.

## Principles

1. **The intelligence layer is the core.** Every source goes through it; no screen reads Home Assistant directly.
2. **Nothing to set up, and never a dead end.** Every feature has a path for every user: automatic when it can be, assisted otherwise (Maison suggests, one tap confirms), manual as a last resort (a form, a tap, a drawing). No "not supported", no empty screen.
3. **Manual stays smart.** What the user enters is a starting point: Maison adjusts it with what it already knows (time spent at home from the iPhone's location, weather, season, household) and recalibrates it with every real value, such as the next bill. A sensor replaces it on its own when one appears.
4. **Every number says where it comes from:** measured, estimated or entered.
5. **Local first.** The household's data stays in the home.
6. **The best of the iPhone:** a native, polished app, and the data only the iPhone has (location, Health, weather, Focus).

## How it works

**Sources → intelligence layer → what the user sees.**

- **Home Assistant is the home's memory.** It is the always-on device that measures and keeps history, which neither the iPhone (no background work) nor HomeKit (no history) can do. Home Assistant is the only source of history for now; HomeKit and Matter will be discussed if Maison opens up to people without Home Assistant.
- **The iPhone adds what Home Assistant doesn't have:** location and presence, sleep from Health, the weather forecast, Focus modes, and the network as the iPhone sees it.
- **The main appliances add what isn't measured** (see Appliances for energy).
- **Maison sets Home Assistant up itself:** history retention, an internet check (Ping), devices Home Assistant discovered, the energy dashboard.
- **A Maison add-on runs the intelligence layer around the clock** on the household's Home Assistant, installed from the app in one tap (Home Assistant OS and Supervised).
- **The only thing on our side is a push relay that stores nothing**, because the app's APNs key can't be shipped to every home. Payloads can be end-to-end encrypted.
- **Where it can, the intelligence layer is one Swift package** built for iOS and for Linux, so the add-on runs the same logic as the app. Wording by the on-device model stays on the iPhone.

## The intelligence layer

It already exists in pieces: `DayFacts` computes the facts, `DayDigest` has them written, `GroundedNumbers` rejects a text with a number that isn't in the facts, `RuleDraft` turns a sentence into a rule. They are spread out and wired to Home Assistant; they become one module behind the source boundary.

What it does:

1. **Unify:** one picture of the home, whatever the source, each value keeping its origin.
2. **Understand the context:** who is home, the weather, the season, the household's habits.
3. **Estimate what is missing:** from the main appliances, the context, and how long devices ran.
4. **Learn:** the home's usual ranges and habits; a dismissed finding or a corrected estimate counts.
5. **Explain:** always why, never a bare number.
6. **Act:** every finding ends in one tap — create a rule, launch a scene, check a device or an object.

Its rule: **it computes, the language model only words it.** It therefore works without Apple Intelligence: when the model doesn't support the language, the findings show in a short written form instead of disappearing.

### What it is, concretely

Mostly ordinary Swift code: statistics and rules over the home's history. A language model is used for three narrow tasks only, and never decides on its own.

**Computed by code, no AI:**

- **The facts of the day** (`DayFacts`): what changed, what ran, what stayed open.
- **Usual ranges:** percentiles of the home's own history, per room and per hour, never fixed thresholds.
- **The three scores:** comfort is the share of the day each room spent in its range; energy compares use with the usual one at equal weather (higher means more sober); network is internet availability over 24 hours.
- **Estimates:** a device's power (main appliances, energy label) multiplied by how long it ran; the cost from the price per kWh.
- **Findings and their order:** each finding is a rule with a threshold learned from the home; the home screen shows one at a time, safety first.
- **Habits:** a manual action repeated in the same context, counted, then offered as a rule.

**Where a language model is used:**

1. **Wording the day summary** (`DayDigest`): the facts go in, a short text comes out. Any number in the text must be in the facts (`GroundedNumbers`), otherwise the text is rejected.
2. **Turning a sentence into a rule** (`RuleDraft`): the model fills a typed structure (QUAND, SI, ALORS); the code then finds the real devices and drops any number that wasn't in the sentence.
3. **Reading a scanned document:** what it is and what it says (product, merchant, amounts, dates, price per kWh), in any language, on the iPhone. The code then checks every value.

The model is Apple's on-device model (the one behind Apple Intelligence), through the Foundation Models framework, with guided generation into Swift types. It runs on the iPhone, offline.

**What it is not:** no cloud language model, no chatbot, nothing sent to a server. Questions in plain language stay in Later.

**Where it runs:** on the iPhone today. The Maison add-on will run the same Swift package on Home Assistant, around the clock, but only the computing part: Apple's model only exists on Apple devices, so notifications sent by the add-on use the short written form, and the iPhone rewords them when it opens.

**Requirements:** a device and a language supported by Apple Intelligence. Without it, Maison keeps every finding in the short written form, rules are built with the step-by-step editor, and a document's fields are entered by hand. An object gets a default emoji for its kind.

**Cost:** Apple's on-device model costs nothing per request. The only running cost on our side is the push relay.

## Objects

An object exists first; documents attach to it. Only the name is required.

- **Fields:** name, emoji, durable or consumable, room, price and date of purchase, brand and model, end of warranty, documents, a parent object (blades belong to a razor, a filter to an air conditioner), and the connected device it is, if any. Each value keeps its origin.
- **Emoji and kind:** proposed by the on-device model when the object is created or first scanned (🪒 for a razor), changed in one tap; a default per kind without Apple Intelligence. The emoji only identifies the object; the rest of the interface stays in SF Symbols.
- **Consumables:** each replacement is a date, from a scanned invoice or a tap on "Replaced". Before two replacements, the category's usual lifetime, shown as an estimate; after that, the median gap between replacements. The next date is the last replacement plus that interval, with a reminder a few days before; postponing or ignoring it is remembered.
- **Storage:** GRDB (SQLite), the project's first dependency, because the same package must build for the add-on on Linux, where SwiftData doesn't exist.

## Appliances for energy

To estimate what has no meter, Maison needs to know the main appliances: water heater, fridge, oven, washing machine, TV.

- **Automatic:** devices Home Assistant already knows, with their power when a plug measures it.
- **Assisted:** a photo of the appliance, its barcode, or the QR code of the European energy label (official consumption).
- **Manual:** a short form, with the usual appliances suggested.

It feeds energy estimates without a meter (power multiplied by running time, then the cost) and nothing else for now. Every estimate says it is one.

## Reading paperwork

The household scans any document; Maison first recognises what it is (an energy bill, a contract, a warranty, something else), then reads what that kind of document holds. Every document is kept, filed by kind and searchable: bills of any kind, contracts, warranties, manuals, anything else. Energy bills and contracts also feed the core. By default everything happens on the iPhone.

1. **Capture:** the iOS document scanner (VisionKit) straightens and crops the page; a PDF can be imported instead.
2. **Text:** on-device text recognition (Vision).
3. **Understanding:** Apple's on-device model reads the recognised text, whatever the language: the kind of document, the product, the merchant, the amounts and the dates, filled into a typed structure. No rules per language or per kind of document, and nothing leaves the iPhone.
4. **Checking by code:** formats (amounts, currencies, dates), totals that add up, plausible dates, and every number present in the recognised text. Each value is marked with its origin. The user confirms before saving and corrects any field in one tap. Without Apple Intelligence, the fields are entered by hand.
5. **Attaching:** a document scanned from an object's sheet goes to that object; scanned from anywhere else, Maison proposes the object it is about, or offers to create it, prefilled. A field already set is never overwritten without confirmation.

**Knowing the energy supplier.** Three sources, combined:

- **A bill or a contract:** the supplier's name is always printed; the model reads it, then it is checked against a list of suppliers shipped with the app, per country (for France: EDF, Engie, TotalEnergies, Ekwateur, Mint, OHM, Vattenfall…), with their spelling variants, so the answer is always a real supplier. The country comes from Home Assistant's configuration, or the iPhone's region. A grid operator, such as Enedis in France, is never taken for the supplier.
- **Home Assistant, partly:** a smart meter read by Home Assistant gives the tariff option; in France, a Linky meter gives the calendar (base, off-peak, Tempo), and with a TIC module the exact off-peak hours, but never the supplier's name. An installed integration can only hint at a supplier; Maison then suggests, it never asserts.
- **Asking, in one tap:** a card in the Energy sheet, "Your electricity supplier?" with the main suppliers of the home's country, a search across all countries, and "Other", or "TotalEnergies? Yes / No" when Maison has a hint.

Knowing the supplier doesn't give the price: one brand has many offers. The price comes from a bill or is entered by hand.

What is read feeds Energy: the supplier, the price per kWh and the off-peak hours. When a bill has several prices, Maison asks which one applies instead of guessing, at least the first time for each supplier.

## Findings

What the user receives. The first catalogue:

- **Energy:** standby use, the month's projected cost, the costliest devices, use at equal weather, cheaper hours.
- **Comfort:** a room out of its range, heating or cooling running in an empty home, a window open while it runs.
- **Devices:** offline, battery low, a frozen sensor, a device behaving unusually.
- **Safety:** a door left open, unlocked after everyone left, water leak, smoke.
- **Habits:** a manual action repeated in the same context, offered as a rule.
- **Network:** internet down or slow, a device that dropped off the Wi-Fi.
- **Upkeep:** raised by a device (a filter, a battery).

Every finding can be dismissed ("Ignore") or corrected ("That's not right"); both are remembered and change the next findings.

**One finding at a time on the home screen, by priority:** safety first, then network, comfort, energy and upkeep. A rule created from a finding uses what Maison knows, such as the off-peak hours of the contract, rather than a fixed time.

Comfort ranges are never hard-coded: they are learned from the home's history or set by the user. Energy is in the currency set in Home Assistant.

## MVP

1. **The intelligence layer as a module**, with the origin of every value.
2. **Today:** the day summary and one finding at a time (energy, comfort, network, devices, safety), with its origin, its reason and a one-tap action. The ring on the home screen becomes a score: the share of the day each room spent in its comfort range, measured.
3. **A useful first launch:** import Home Assistant's existing history (detailed history and long-term statistics), so Maison has something to say within minutes.
4. **Tidy the setup:** suggest rooms, hide duplicates, clear names.
5. **Network:** internet latency and speed, outages, devices on the Wi-Fi, from Home Assistant and the iPhone.
6. **Energy:** read Home Assistant's energy dashboard, suggest the right meter when it isn't set, or a manual entry (bill, price per kWh). Ask for the supplier and the tariff option the first time, prefilled from the meter when it is read.
7. **Minimal manual entry:** comfort range, usual hours, the main appliances.
8. **Widgets:** Home Screen, StandBy, Lock Screen.

## Next

- Appliances for energy in full (photo, barcode, energy label).
- Reading energy bills and contracts on the iPhone, their values passed to Energy.
- The push relay and notifications with actions.
- The Maison add-on and the automatic Home Assistant setup.
- Estimates adjusted by presence and weather, recalibrated by real values.
- Learning from feedback; habits turned into rules.
- A floor plan without LiDAR: rooms drawn by hand, a photo of the plan to trace, or a plain list of rooms.
- Before leaving, away mode, getting the home ready for the return, offered by a notification when the iPhone leaves home.
- Critical alerts for leaks and smoke (Apple entitlement), so they sound even in silent mode or a Focus.
- Control Center, Siri, Shortcuts and App Intents, Focus filters.
- Week and month reviews.

## Later

- "Plug in the box": a ready-made Home Assistant box that Maison sets up on its own, Home Assistant invisible to the user.
- HomeKit and Matter as sources, for people without Home Assistant.
- Questions in plain language, simulations ("what if I lower it by one degree"), a year in review.
- Temporary guest access, a household feed, comfort and sleep per person.
- Live Activities, Apple Watch, iPad and Apple TV as wall dashboards, a Mac app.

## Not this product

A Maison email address. A connection to a bank. Paperwork beyond what serves energy (see Later).

## Gaps in the current code

Dead ends that contradict the principles above:

- The energy sensor is picked by its name (English or French words), so a sensor named in another language, or "Linky consumption", is never found (`HomeStore.energyToday`).
- The temperature ring is fixed at 10–30 °C, saturated in a hot climate and wrong in °F (`Components.swift`).
- Away from home, the app stays on the address it signed in with: the connection, token refresh and rule editing never fall back to `external_url` (only shown in Settings and used by the presence webhook), and Nabu Casa's `remote_ui_url` isn't read at all. Signed in with a local address, the app is offline as soon as you leave (`HomeStore.connect`).
- Screens read Home Assistant's `EntityState` directly (13 files under `Features/`), so the source boundary of the intelligence layer is still to build; `HomeStore` carries connection, commands, history, presence and favourites in one type.
- Nothing runs while the app is closed, apart from presence: no finding, no notification until the add-on and the push relay exist.
- Saving a rule needs a Home Assistant administrator account; other members get an error instead of a path forward (`RuleEditor`).
- The day summary and rule writing disappear when Apple Intelligence doesn't support the language.
- The app is in English and French only.

## Open questions

- Where do scanned documents live: only on the iPhone that scanned them, or in the household's iCloud zone so every member can open them?
- Does Maison work without Home Assistant? The core needs measured history, which only Home Assistant provides today.
- How far does sleep go inside Comfort: the bedroom only, or sleep itself from Health?
- Wording in languages Apple Intelligence doesn't support: a simple written form only, or an optional cloud model?
- How stable are the Home Assistant APIs Maison relies on to set it up (onboarding, add-on install, energy preferences)?
- What does the floor plan bring to the intelligence layer?
- Pricing: one-off purchase or subscription, given that the push relay has a running cost.
