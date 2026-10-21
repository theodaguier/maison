# Roadmap

## Vision

**Maison is the intelligent dashboard of your connected home, whichever brands you have.**

- **Devices:** see and control every device in one place, whatever the source.
- **Network:** whether the internet and the Wi-Fi are fine, what is connected, what dropped.
- **Energy and comfort:** what the home uses, what it costs, and whether it feels right — temperature, humidity, air.

### The Bevel layer

Bevel turns a watch's sensors into a few readable scores and a little advice, so nobody has to read charts. That layer sits on top of the home: a few rings, a summary of the day, and two or three findings. Each finding ends in one tap — create a rule, launch a scene, or check a device.

## Sources

The home has its own model — rooms, devices, measurements, events — separate from any one source. Each source is a connector that declares what it can do: Home Assistant, HomeKit, Matter, an internet box, a meter, a brand's cloud. The app shows the best it can from the ones that are connected, and never an empty screen.

The Home Assistant code already in the app becomes the first connector. Nothing is thrown away.

## MVP

1. **Sources:** Home Assistant (already in place), HomeKit, a first internet box (Freebox, through the official API), and the weather.
2. **One list of devices:** a single list per room, whatever the source.
3. **Network:** the state of the connection, the devices on it, and a log of the outages.
4. **Comfort and energy:** a Comfort ring — time at the right temperature and humidity, room by room. Consumption and cost when a source provides them, in euros when the tariff is known.
5. **Today:** the rings, the morning summary (`DayDigest`), and findings with a one-tap action (`RuleDraft`).

## Next, in order

- Other boxes and routers, other meters, and the clouds of the usual brands.
- Sleep and the bedroom, then air quality.
- History without Home Assistant (a hub is optional).

Sleep reads nights from Health, with consent, and matches them with the bedroom: temperature, humidity, light, noise. A finding such as "You sleep 25 min longer when the bedroom is below 19°" ends in a rule, in one tap.

Air quality is CO₂, humidity and particles, from sensors or from outdoor data when there are none.

## Parking

Set aside. An idea leaves this list only when it follows naturally from a connected device.

- A full sheet for an object (warranty, manual, consumables), from devices the home already knows.
- Upkeep tied to devices: the robot vacuum, filters, descaling.
- An inventory of objects that aren't connected.
- A Maison email, and a bank connection.
- Documents, contracts, subscriptions, the total cost of the home.
- Guest mode (limited to some devices, expiring on its own), a holiday checklist, a condition report, a home that can be passed on.
- A year in review, a question in plain language.
