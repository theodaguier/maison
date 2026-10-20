# Roadmap

## Vision: the Bevel of the home

Bevel turns a watch's sensors into a few readable scores, trends and advice, so nobody has to read charts. Maison should do the same for the home: understand how the place lives, and how it affects the people in it.

### 1. Three daily scores, as rings

- **Comfort** (0–100): time spent in the right temperature and humidity range, room by room, while someone is home.
- **Energy**: today's use against the usual days and a goal, like Bevel's strain — in euros when the tariff is known.
- **Air**: CO₂, humidity and particles, from sensors or from outdoor air-quality data when there are none.
- Each score has its own sheet: curve, usual range, and what made it go up or down (the temperature sheet in the Figma file is the model).

### 2. Sleep and the bedroom — the heart of the product

- Read nights from Health (with consent) and match them with the bedroom: temperature, humidity, light, noise.
- Findings such as "You sleep 25 min longer when the bedroom is below 19°" or "Restless nights above 60 % humidity".
- Each finding ends with a suggestion that becomes a rule in one tap ("Lower the setpoint to 18.5° at 10 pm?").

### 3. A journal

- Two or three quick questions in the evening (window open? extra heater? guests?).
- After a few weeks, measure the effect of each habit on the scores.

### 4. Trends and reviews

- Week and month: average comfort, energy in euros, best and worst nights, what changed.
- A Sunday review written by the on-device model, like the day summary but for the week.

### 5. A coach

- Questions about the home ("Why did my bill go up?", "Which room is the least comfortable?") answered from its history, ending with rules to create.

### What it needs

- Good sensors help (temperature and humidity per room, CO₂ in the bedroom, power), but each score must work with less: see the sources below.

## Sources

Maison should read and act on as many sources as possible, Home Assistant being one of them. Every score degrades gracefully: energy works from the Linky meter alone, sleep from the watch alone, air from outdoor data alone; each sensor added makes them more precise.

### Data

On the iPhone, no third party:

- **Health (HealthKit)**: sleep stages and wake-ups, heart rate and variability, steps, wrist temperature. The key to the home ↔ sleep link.
- **Apple Home (HomeKit)**: accessories that aren't in Home Assistant, read and controlled directly.
- **Calendar (EventKit)**: trips, absences, guests — to anticipate (heating off during a trip, guest room warmed up).
- **Location**: arrivals and departures (already in place for Home Assistant presence).
- **Apple Weather (WeatherKit)**: outdoor temperature, forecast, sunshine — to compare and anticipate ("30° tomorrow: close the shutters at 11 am").
- **Music (MusicKit)**: what's playing, for moods tied to listening.

French online services, mostly free:

- **Linky meter (Enedis Data Connect)**: real consumption every half hour, with no sensor at home.
- **Tempo and EJP tariffs (EDF)**: blue, white and red days, so energy in euros is exact.
- **Ecowatt and the electricity mix (RTE éCO2mix)**: grid stress and carbon intensity in real time, to shift the washing machine to green hours.
- **Air quality and pollen (Atmo France)**: whether to air the rooms or keep the windows closed.

### Actions

- **Home Assistant**: already in place.
- **Apple Home**: control HomeKit accessories directly.
- **Shortcuts**: Maison runs the user's shortcuts, and shortcuts run Maison's actions (App Intents).
- **Agents**: Grok Bot and Hermes for complex requests ("get the home ready for my return") — see Agents below.
- **Reminders**: "Buy AA batteries" added on its own when a sensor runs low.
- **Siri, widgets, Control Center**: see below.

## Beyond the app

### Without opening the app

- **Control Center and Lock Screen controls** (ControlWidget): floor lamp, shutters, front door in one gesture, calling Home Assistant without launching the app.
- **Interactive widgets**: temperature, lights on and scenes on the Home Screen and in StandBy.
- **Siri and Shortcuts**: "Hey Siri, run Cinema in Maison"; Maison actions in the Shortcuts app, triggerable by an NFC tag or a time of day.
- **Apple Watch app**: favourites, scenes and the front door on the wrist.

### At home

- **Before leaving**: when the last person leaves, list what is still on or open and turn it all off in one tap.
- **Battery report**: every sensor and lock running low, in one place.
- **Living plan**: each room's temperature as a colour on the floor plan, lights that are on drawn on it.
- **Energy in euros**: per day and month with the tariff, and the devices that cost the most.

### Household

- **Temporary guest access**: for a babysitter or friends, limited to some devices, expiring on its own.
- **Who did what**: a household feed ("Camille unlocked the door at 6:40 pm"), from the logbook.

### Prerequisite: notifications

Alerts (door left open, device not responding, before leaving) need push notifications, which need a small push server with the app's own APNs key: Home Assistant can only push to its own companion app. Plan it before the features that depend on it.

## Machine learning

The app already reads two sources that lend themselves to learning from the household's own data (`Maison/Core/HomeAssistant/Insights.swift`):

- **the logbook**: every state change, when it happened, and whether a person or an automation made it;
- **long-term statistics**: hourly or daily mean, min and max for sensors.

Three problems, in the order they should be tackled.

### 1. Suggest automations from habits

- **Observation:** a manual action repeated in the same context (turning on the living room light around 7 pm when coming home, turning off the speaker when the TV goes off) is an automation nobody wrote.
- **Problem:** find the logbook actions *made by a person* that recur in a similar context (time, weekday, presence, state of other devices), and turn them into a proposed rule.
- **In the app:** a card such as “You often turn on the living room around 7 pm when you get home. Create an automation?”, opening the WHEN / IF / THEN editor pre-filled.
- **Baseline:** count manual actions per entity, hour slot and weekday. The model has to beat it, for instance by taking presence or other devices into account.
- **Approach:** frequent pattern mining, then a classifier to score candidates.

### 2. Predict which device will be used next

- Onboarding already plans “favourites suggested from usage”, which is a hand-written rule for now.
- **Problem:** rank devices by the probability of being used *right now* (time, weekday, room, recent actions), like Siri Suggestions for the home.
- **Baseline:** the most used devices at this hour.
- **Approach:** a small model trained in Python, converted to Core ML and run on the iPhone.

### 3. Detect unusual sensor behaviour

- The charts already show a “usual range”.
- **Problem:** learn that range per hour and weekday instead of hard-coding it, then flag deviations: unusual consumption, a temperature dropping (window left open?), a frozen sensor or a dead battery.
- The simplest of the three, a good warm-up.

### Before starting

- **Data volume:** everything depends on the number of devices and how much history the server keeps. The recorder keeps detailed history for only a few days by default; long-term statistics last longer. Raise `purge_keep_days` early so data accumulates.
- **Gaps:** periods when the server is down must be treated as missing values, not as “nothing happened”.
- **First step:** a script that exports the logbook, to count manual actions and see whether patterns already stand out.

## Agents (MCP)

Let assistants such as Claude or Hermes use the home through the Model Context Protocol.

### 1. Start with Home Assistant's own MCP server

- **Observation:** Home Assistant ships a "Model Context Protocol Server" integration: an MCP client can control the devices exposed to Assist and read their state, with a Home Assistant token.
- **Step:** enable it on the server and try it from Claude and Hermes before writing anything.
- **Limits to check:** what it can't do well — creating rules, reading history, knowing who did what.

### 2. A Maison MCP server for what Home Assistant's doesn't cover

- **Problem:** give agents the things Maison already knows how to do, with the same safeguards.
- **Tools:**
  - create and edit rules through the WHEN / IF / THEN model (`AutomationRule`), keeping unknown steps intact, and saving through the configuration API (administrator account);
  - history and logbook: how long a device was on, who unlocked a door and when, energy use, a sensor's usual range;
  - turn-off timers and "open too long" alerts, as Home Assistant scripts and automations (`TurnOffTimer`, `OpenTooLongAlert`);
  - rooms and devices as Maison shows them, technical entities hidden.
- **Where:** a small server (TypeScript or Python) in Docker on the Beelink, next to Hermes, talking to Home Assistant through the same APIs as the app (WebSocket, history, logbook, automation config).
- **Access:** local network or Tailscale only, with a token from a dedicated Home Assistant account; anything that writes (rules, unlocking) asks for confirmation.
- **Not feasible:** hosting it in the iOS app (no long-running server on iOS); exposing the floor plan and favourites means reading iCloud through CloudKit Web Services, a project of its own.

### 3. Grok Bot from the app

- **Goal:** in rule creation (the sparkles button), "Ask Grok Bot" instead of Apple Intelligence, without leaving Maison.
- **How:** a Grok Bot routine triggered by a webhook (URL and key, `Authorization: Bearer`). Maison posts the description and the device list to it.
- **Reply channel:** a webhook doesn't answer the caller, so Grok Bot writes the rule into Home Assistant as a disabled automation, through the Maison MCP server's "create a rule" tool. Maison, connected live, sees it appear and opens it pre-filled in the WHEN / IF / THEN editor for review.
- **Settings:** webhook URL and key entered on the user's own iPhone, never shipped in the app; a choice "Rule writing: Apple Intelligence / Grok Bot".
- **To check:** whether Grok Bot routines run on xAI's servers or in the Mac app (the Mac would have to stay on).
- **Privacy:** the description and device names leave the iPhone for xAI; say so before the first use and in the privacy policy.
