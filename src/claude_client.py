"""
Talks to the Claude API via our Cloudflare Worker proxy.

Why a Worker proxy instead of calling Anthropic directly?
The API key never sits in this codebase or on the deployed backend.
The Worker holds the key as a Cloudflare secret, and our server just
posts to the Worker URL. Same pattern I used in Thine.

We ask Claude to return JSON with the reply, a self-rated confidence,
and a one-line reasoning. We then apply a few business rules on top
of that confidence (complaints capped, money mentions capped).
"""

import os
import json
import requests


# The Worker URL goes in .env. The Worker itself holds the actual API key
# as a Cloudflare secret, so even if this URL is exposed, the key isn't.
WORKER_URL = os.environ.get("WORKER_URL")

MODEL = "claude-sonnet-4-20250514"


SYSTEM_PROMPT = """You are a guest relations assistant for Nistula, a company that manages luxury private villas in Goa, India.

Your job is to draft replies to guest messages. The reply should be:
- Warm and personal, but not over-the-top
- Direct - guests want answers, not fluff
- Accurate - use only the property context provided. If you don't know something, say you'll check with the team
- Short - 2 to 4 sentences usually, longer only if the guest asked a complex multi-part question
- Indian English tone where natural, but professional

You must respond with valid JSON only, in this exact format:
{
  "reply": "the actual message to send to the guest",
  "confidence": 0.0 to 1.0,
  "reasoning": "one short sentence on why this confidence"
}

Confidence guidance:
- 0.90+ : The answer is directly in the property context, no ambiguity
- 0.70-0.89 : You answered fully but had to interpret something, or the guest asked something compound
- 0.50-0.69 : Partial answer, missing some info, or the question is unclear
- Below 0.50 : You had to guess significantly, or the question is about something outside the property context

Do not auto-confirm bookings, prices for non-standard cases, or anything you are not 100% sure about. When unsure, draft a holding reply that promises a human follow-up.

Never include "I am an AI" or similar disclaimers. The guest is talking to "Nistula" as a brand."""


def draft_reply(
    guest_name: str,
    message_text: str,
    query_type: str,
    property_context: str,
) -> tuple[str, float]:
    """
    Returns (reply_text, confidence_score).
    Raises an exception if the Worker / Claude API call fails - the caller handles it.
    """

    if not WORKER_URL:
        raise RuntimeError("WORKER_URL is not set. Check your .env file.")

    user_prompt = f"""Guest name: {guest_name}
Query type (auto-classified): {query_type}

Property context:
{property_context}

Guest message:
"{message_text}"

Draft a reply. Remember to respond with JSON only."""

    # Post to the Worker. The Worker forwards this to Anthropic with the
    # real API key attached on its end. We never see the key here.
    resp = requests.post(
        WORKER_URL,
        json={
            "model": MODEL,
            "max_tokens": 1000,
            "system": SYSTEM_PROMPT,
            "messages": [{"role": "user", "content": user_prompt}],
        },
        timeout=30,
    )
    resp.raise_for_status()

    data = resp.json()

    # The Worker passes Anthropic's response straight through, so we get
    # the standard content block list.
    raw_text = data["content"][0]["text"].strip()

    # Sometimes the model wraps JSON in markdown fences. Strip them.
    if raw_text.startswith("```"):
        raw_text = raw_text.strip("`")
        if raw_text.lower().startswith("json"):
            raw_text = raw_text[4:].strip()

    parsed = json.loads(raw_text)

    reply = parsed["reply"]
    confidence = float(parsed["confidence"])

    # Apply a few sanity caps on top of Claude's self-assessed confidence.
    confidence = apply_confidence_rules(confidence, query_type, message_text)

    return reply, round(confidence, 2)


def apply_confidence_rules(confidence: float, query_type: str, message_text: str) -> float:
    """
    A small set of overrides on top of Claude's self-assessed confidence.
    These are business rules - things we know matter even if the AI
    thinks the answer is fine.
    """
    text = message_text.lower()

    # Complaints always escalate regardless of what the AI thinks
    if query_type == "complaint":
        return min(confidence, 0.50)

    # Anything involving money or refunds - be cautious
    if any(word in text for word in ["refund", "discount", "compensate", "free of charge"]):
        return min(confidence, 0.60)

    return confidence
