# Store listing copy — When Is Bin App

Draft copy for the Google Play and Apple App Store listings. Voice matches the app's About
screen: plain, first-person-plural-free, no marketing adjectives.

Product name (both stores): **When Is Bin App**
Developer of record: **Jessica Mumby** (independent app — not a Public Digital product)

Attribution line (use verbatim wherever a listing has room for it):

> When Is Bin App is an independent app by Jessica Mumby. It reads bin collection dates from
> the WhenIsBins API, a free service operated by Public Digital.

Contact split (state it in every long description):

- App questions, bugs and feature requests → **Jessica Mumby**, the developer of this app.
- Data corrections, accessibility and privacy questions about the collection dates →
  **hello@whenisbins.com**.

---

## Google Play

### Title (max 30 characters)

```
When Is Bin App
```

### Short description (max 80 characters)

```
Bin day reminders for your postcode — know what goes out, and when.
```

### Full description (max 4000 characters)

```
Never miss bin day again.

When Is Bin App tells you when to put your bins out. Enter your postcode, pick
your address, done: you get the next few collection dates for your property,
with the bins listed by name and colour.

Set a reminder and the app notifies you the night before (or the morning of)
collection — whichever you prefer. You can also add the dates to your calendar
by subscribing to your property's public .ics feed, and the app remembers your
address so your bin days are one tap away next time.

WHAT IT DOES
• Postcode and address lookup, so you see your own council's schedule
• Bin-by-bin collection dates, listed by name and colour
• A local reminder the evening before, or the morning of, collection
• Calendar subscription (.ics) for the same dates
• One saved address, kept on your device

GOOD TO KNOW
• Coverage and the dates available vary by council
• Your council still handles missed collections and changes to its service
• Your postcode and chosen address are sent to the bin day service to resolve a
  schedule. Nothing else about you is collected, and there is no tracking or
  advertising in the app.

WHO MAKES IT
When Is Bin App is an independent app by Jessica Mumby. It reads bin collection
dates from the WhenIsBins API, a free service operated by Public Digital.

Questions about this app go to Jessica Mumby, who develops it. Corrections and
accessibility or privacy questions about the data go to hello@whenisbins.com.
```

### Play Console notes

- **App name** — `When Is Bin App` (matches the Android label on the launcher).
- **Contact email** — the developer's address (app questions); the listing's `hello@whenisbins.com` mention is for data questions and belongs in the description text, not the developer contact field.
- **Data safety** — declare the postcode/address sent to the WhenIsBins API for app functionality; no data collected for tracking, no ads.
- **Content rating / category** — Utilities (or Tools).

---

## Apple App Store

### Name (max 30 characters)

```
When Is Bin App
```

### Subtitle (max 30 characters)

```
Bin day reminders
```

### Promotional text (max 170 characters)

```
Enter your postcode, pick your address, and get a reminder the night before collection — plus a calendar feed of your bin days.
```

### Description (max 4000 characters)

```
When Is Bin App tells you when to put your bins out.

Enter your postcode, pick your address and see your next collection dates, bin
by bin. Set a reminder and the app notifies you the night before collection, or
on the morning itself. You can also add your bin days to your calendar with your
property's public .ics feed, and the app remembers your address so your dates
are one tap away next time.

WHAT IT DOES
• Postcode and address lookup, so you see your own council's schedule
• Bin-by-bin collection dates, listed by name and colour
• A local reminder the evening before, or the morning of, collection
• Calendar subscription (.ics) for the same dates
• One saved address, kept on your device

GOOD TO KNOW
• Coverage and the dates available vary by council
• Your council still handles missed collections and changes to its service
• Your postcode and chosen address are sent to the bin day service to resolve a
  schedule. Nothing else about you is collected, and there is no tracking or
  advertising in the app.

WHO MAKES IT
When Is Bin App is an independent app by Jessica Mumby. It reads bin collection
dates from the WhenIsBins API, a free service operated by Public Digital.

Questions about this app go to Jessica Mumby, who develops it. Corrections and
accessibility or privacy questions about the data go to hello@whenisbins.com.
```

### App Store Connect notes

- **Display name** — `When Is Bin App`, matching `CFBundleDisplayName` in `ios/Runner/Info.plist`.
- **Keywords (max 100 characters)** — `bins,bin day,recycling,collection,reminder,refuse,postcode,council,calendar,kerbside,waste,garden`
- **Support URL** — a page that states the attribution and both contact routes; the Privacy URL should be `https://whenisbins.com/privacy` (the same link the About screen opens).
- **App Privacy** — must match `ios/Runner/PrivacyInfo.xcprivacy`. The v1.0 submission was rejected under Guideline 5.1.2(i) (29 Sept 2026) because the label said the address was used to track, and the app has no App Tracking Transparency prompt. Answer exactly:
  - Data collected: **Contact Info → Physical Address** only.
  - Purpose: **App Functionality** only.
  - Linked to the user's identity: **No** (there are no accounts; the address goes to the WhenIsBins API and is cached on the device).
  - Used for tracking: **No**. Never tick this: the app has no ads, analytics or data brokers, and ticking it makes ATT mandatory.
  - Editing the label needs the Account Holder or Admin role. Publish it before resubmitting.
