# Part 3 — The 3am Hot Water Complaint

## Question A The Immediate Response

**The reply:**

> Hi, really sorry about this, especially at this hour. I am pulling our on-call team in now and someone will call your villa phone within 10 minutes with a fix or a workaround for the morning. I have noted the refund request and our ops lead will reply on that by 9am. We will make this right.

**Why this wording:** Three things matter. Acknowledge fast at the intensity the guest feels (hot water at 3am with morning guests is a real emergency). Give specific timelines  10 minutes, 9am  to lower stress without overcommitting. Do not auto-promise the refund; that is a human call.

## Question B The System Design

The AI sends the holding reply only after the escalation actually fires. The classifier tags this complaint, confidence forced low, action escalate. From there:

1. **Page the on-call ops lead** via WhatsApp + auto-dial. Property metadata holds the rotation.
2. **Page the property caretaker** with villa name, guest name, hot water, urgent.
3. **Log everything** to the conversation: original message, AI draft, classification, who got paged when.
4. **Create a high-priority ticket** with a 30-minute SLA timer.
5. **If no human acknowledges in 30 mins:** escalate to founder, and send a second message to the guest with the ops lead's direct number. Silence is worse than slow.
6. **At 9am:** auto-reminder to the ops lead to send the written follow-up, because the guest was promised one.

## Question C The Learning

Three complaints in two months on the same villa, same issue, is not three guest problems. It is one property problem. The system should:

- **Auto-flag the pattern** when complaints clustered by (property_id, complaint_topic) cross a threshold. A weekly digest to the ops lead listing repeat issues stops them sitting in scattered tickets.
- **Trigger a preventive workflow** for that villa: scheduled geyser service before every booking until three clean stays, plus a pre-arrival check by the caretaker on check-in morning.
- **Add a proactive touch:** for new bookings at this villa, the AI sends a check-in-eve message: "hot water runs on a timer, let us know if anything feels off." Surfacing friction before the guest hits it turns a complaint into a non-event.

Pattern detection stops complaint four. The rest is hospitality dressed as automation.
