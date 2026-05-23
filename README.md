# Nistula Technical Assessment

A small backend that takes inbound guest messages from any channel, classifies them, gets Claude to draft a reply, and decides whether to auto-send or escalate to a human.

Built in Python with FastAPI. The Claude API is accessed through a Cloudflare Worker proxy so the API key never sits in this backend or in this repo. Three parts as per the brief: webhook handler, database schema, and a written response to the 3am scenario.

---

## Architecture

```
   Webhook caller (WhatsApp / Airbnb / etc - simulated here)
        |
        |  POST /webhook/message
        v
   FastAPI server (this repo)
   - classify
   - normalise
   - decide action
        |
        |  POST + x-proxy-auth header
        v
   Cloudflare Worker proxy (worker/cloudflare-worker.js)
   Holds ANTHROPIC_API_KEY + PROXY_AUTH_TOKEN as secrets
   Rejects calls without the right auth header
        |
        |  x-api-key: <Anthropic key>
        v
   Anthropic API
```

Why this shape? Same pattern I used for my Thine project (`blister2007.github.io/memory-audit`). The API key is a Cloudflare secret, not an env var on the backend. The Worker is additionally gated by a shared auth token, so even if the Worker URL leaks, random callers cannot use it.

---

## Quick Start

This backend talks to Claude through a Cloudflare Worker proxy that holds the API key as an encrypted secret. To run it, you deploy your own Worker (a few minutes) and point the backend at it.

### 1. Deploy the Worker

```bash
cd worker
npm install -g wrangler
wrangler login

wrangler secret put ANTHROPIC_API_KEY      # paste your Anthropic key
wrangler secret put PROXY_AUTH_TOKEN        # paste any long random string

wrangler deploy                              # prints your Worker URL
```

### 2. Configure the backend

```bash
cd ..
cp .env.example .env
```

Edit `.env` and set both values:

```
WORKER_URL=https://your-worker.workers.dev
PROXY_AUTH_TOKEN=the-same-random-string-from-step-1
```

### 3. Run it

```bash
pip install -r requirements.txt
python run.py
# Server is live at http://localhost:8000
```

### Test it (in a second terminal)

```bash
python tests/test_webhook.py
```

This fires 5 sample messages covering availability, pricing, WiFi, special requests, and a complaint.

---

## Project Structure

```
nistula-technical-assessment/
  README.md              # you are here
  schema.sql             # Part 2 - PostgreSQL schema with comments
  thinking.md            # Part 3 - the 3am scenario answers
  requirements.txt       # Python dependencies
  .env.example           # template for WORKER_URL and PROXY_AUTH_TOKEN
  run.py                 # entry point - loads .env and starts uvicorn
  src/
    main.py              # the FastAPI app and the /webhook/message endpoint
    classifier.py        # keyword-based query type classifier
    claude_client.py     # posts to the Worker, parses Claude's JSON reply
    property_data.py     # mock property context (Villa B1)
  worker/
    cloudflare-worker.js # the proxy - holds the API key as a secret
    wrangler.toml        # Cloudflare deployment config
  tests/
    test_webhook.py      # 5 sample inputs hitting the live server
```

---

## How It Works

When a message comes in at `POST /webhook/message`, the flow is:

1. **Normalise** - wrap the raw payload into the unified schema, add a UUID.
2. **Classify** - keyword matching tags the query type (availability, complaint, etc).
3. **Build the prompt** - pull property context and pass everything to Claude via the Worker.
4. **Get the draft** - Claude returns JSON with reply text, confidence score, and reasoning.
5. **Sanity-check confidence** - apply business rules (complaints always escalate, anything touching money gets hedged).
6. **Decide the action** - `auto_send`, `agent_review`, or `escalate`.
7. **Return the response** to whoever called the webhook.

The endpoint returns:

```json
{
  "message_id": "uuid",
  "query_type": "pre_sales_availability",
  "drafted_reply": "Hi Rahul! Great news...",
  "confidence_score": 0.91,
  "action": "auto_send"
}
```

---

## Confidence Scoring

The brief said: define your own logic. Here is mine.

**The score comes from Claude itself, not from external heuristics.** Claude sees the message, the property context, and the classification. It knows things an external scorer cannot: did it have to guess, was a field missing from the property context, did the guest ask something compound where only half was answerable. Asking Claude to self-rate its own confidence and return it as part of the JSON response captures that signal far better than counting keywords on the outside.

The system prompt gives Claude clear bands to anchor against:

| Score | What it means |
|-------|---------------|
| 0.90+ | Answer is directly in the property context, no ambiguity |
| 0.70 to 0.89 | Answered fully but had to interpret, or it was a multi-part question |
| 0.50 to 0.69 | Partial answer, some info missing, or the question is unclear |
| Below 0.50 | Had to guess significantly, or the question is outside scope |

On top of Claude's score, I apply a small set of **business rules** to catch overconfidence:

- **Complaints are capped at 0.50.** No matter how confident Claude is, an angry guest goes to a human.
- **Anything mentioning refunds, discounts, or compensation is capped at 0.60.** Money decisions are not for an AI to auto-send.

These caps live in `claude_client.py` in `apply_confidence_rules()`. They are deliberately conservative. The cost of an AI sending a wrong refund offer is much higher than the cost of a human spending 30 seconds reviewing.

**The final action** maps confidence + query type to one of three buckets:

- `confidence >= 0.85` and not a complaint -> **`auto_send`**
- `0.60 <= confidence < 0.85` -> **`agent_review`** (draft shown to a human who clicks send or edits)
- `confidence < 0.60` or it is a complaint -> **`escalate`** (no draft, straight to a human)

---

## Design Notes

**Why a Cloudflare Worker proxy with shared-secret auth?** Four reasons. One, the API key is a Cloudflare secret, not an env var sitting on every machine that runs the backend. Two, the `x-proxy-auth` header check means even if someone scrapes the Worker URL from logs or a screenshot, they cannot actually use it. Three, it is a clean swap point. If we ever move from Claude to Claude + GPT fallback, only the Worker changes. Four, it gives a free CDN-edge layer where we can later add rate limiting and request logging without touching the backend.

**Why FastAPI?** Pydantic gives request validation for free, it is async-native for the I/O-bound Claude calls, and it auto-generates API docs at `/docs`. For a webhook that validates incoming JSON, calls an API, and responds, it is the right shape.

**Why a keyword classifier instead of using Claude to classify?** Latency and cost. Classification is the first thing that runs and gates the rest of the flow. A 5ms keyword pass beats a 500ms API round-trip when keywords get us roughly 80 percent accuracy on the six well-defined categories. If accuracy slips below a threshold in production, swap in a Claude-based classifier behind the same `classify_query()` function. Nothing else changes.

**Why ask Claude to return JSON instead of just a reply?** Two reasons. One, it forces the model to consciously think about confidence rather than rationalising whatever number a post-hoc scorer assigns. Two, it gives us the `reasoning` field which is gold for debugging when a draft looks wrong. We can see Claude's stated logic without re-running.

**Error handling.** If the Worker call fails (Worker down, Anthropic timeout, bad key), the handler returns `action: escalate` and confidence 0.0 with an error message. Messages are never silently dropped. Losing a guest message is a worse failure than a slow reply.

**What is not built (and why).** This is the inbound side of one webhook with mock property data. A production version would need: a database (the Part 2 schema), actual outbound channel adapters to send the reply, a queue between webhook and Claude so the webhook returns fast and the AI work happens async, retries with exponential backoff on Worker failures, and observability. All deliberately out of scope for a 48-hour assessment.

---

## Testing It

Once the server is running, you can curl any of the test cases manually:

```bash
curl -X POST http://localhost:8000/webhook/message \
  -H "Content-Type: application/json" \
  -d '{
    "source": "whatsapp",
    "guest_name": "Rahul Sharma",
    "message": "Is the villa available from April 20 to 24? What is the rate for 2 adults?",
    "timestamp": "2026-05-05T10:30:00Z",
    "booking_ref": "NIS-2024-0891",
    "property_id": "villa-b1"
  }'
```

Or run `python tests/test_webhook.py` to fire all 5 in sequence.

---

## A Note on Code Style

I deliberately kept this readable over clever. Small files, plain Python, comments where the why is not obvious from the code. If a teammate joins next week, this should take them 15 minutes to understand top-to-bottom, not 2 hours.

---

Sparsh Goel
