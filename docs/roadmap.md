# Roadmap

What's queued after the current release. Most of it comes from tester feedback in October 2026.

## Up next

### Share the app

Bins are often a shared household job, so give people a prompt to share the app with whoever else puts them out.

- Put it where the app has just been useful: after reminders are switched on, and in Settings.
- Make the message useful even if the other person never installs. For example: "Our next bin day is Tuesday 7 October (black bin). I get reminders from When Is Bins: <link>".
- Blocker: Android has no public Play release yet, so a Play link fails for most people. Ship this once Android is in production, or link to a page that points at both stores.
- Android can reuse the share intent in `MainActivity` that the calendar card uses. iOS needs a `UIActivityViewController`. share_plus 13 brings in JNI, objective_c and native-asset build hooks, so a small iOS channel may be the lighter option.

### Make the schedule screen's cards look different

The three cards share one style but do different jobs. Next collection is the answer, reminders are a setting and the calendar is an action. Make Next collection the main panel and turn the other two into plain sections. Don't rely on colour alone to tell them apart (WCAG 1.4.1).

### Test Google's subscribe link on an Android phone

Open `https://calendar.google.com/calendar/render?cid=<webcal URL>` on an Android phone signed in to Google. If it shows Google's own "add this calendar" prompt on the phone, add an "Add to Google Calendar" button and keep "Send yourself the link" as the fallback. Untested so far, because it needs a signed-in Google account on the device.

## Later

### Write bin days straight into the phone's calendar (Android)

This would work without a computer. It needs the calendar permission and new answers in the Play data safety form. The app would also have to update or remove its events whenever the council changes a date. Only worth it if the calendar card turns out to matter.
