# Roadmap

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
