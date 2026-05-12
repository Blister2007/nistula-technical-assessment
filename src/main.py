"""
Nistula guest message handler.

POST /webhook/message receives an inbound guest message, normalises it,
asks Claude to draft a reply, and returns the draft with a confidence score.
"""

import uuid
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from classifier import classify_query
from claude_client import draft_reply
from property_data import get_property_context


app = FastAPI(title="Nistula Message Handler")


# What we accept on the wire. We keep this loose because different channels
# send slightly different things, but these six fields are what we need.
class InboundMessage(BaseModel):
    source: str
    guest_name: str
    message: str
    timestamp: str
    booking_ref: str | None = None
    property_id: str


VALID_SOURCES = {"whatsapp", "booking_com", "airbnb", "instagram", "direct"}


@app.get("/")
def health():
    return {"status": "ok", "service": "nistula-message-handler"}


@app.post("/webhook/message")
def handle_message(payload: InboundMessage):
    # Basic validation. If the source is something we don't recognise,
    # we still process it but flag it. Better than dropping the message.
    if payload.source not in VALID_SOURCES:
        # Not a hard fail - log it and continue. Real systems get weird inputs.
        print(f"Unknown source: {payload.source}. Processing anyway.")

    # Step 1: normalise into our unified schema
    normalised = {
        "message_id": str(uuid.uuid4()),
        "source": payload.source,
        "guest_name": payload.guest_name,
        "message_text": payload.message,
        "timestamp": payload.timestamp,
        "booking_ref": payload.booking_ref,
        "property_id": payload.property_id,
        "query_type": classify_query(payload.message),
    }

    # Step 2: get the property context we'll feed to Claude
    property_context = get_property_context(payload.property_id)
    if property_context is None:
        raise HTTPException(
            status_code=404,
            detail=f"Property {payload.property_id} not found",
        )

    # Step 3: ask Claude for a draft reply
    try:
        reply_text, confidence = draft_reply(
            guest_name=payload.guest_name,
            message_text=payload.message,
            query_type=normalised["query_type"],
            property_context=property_context,
        )
    except Exception as e:
        # If Claude is down or the API errors out, we don't want to lose
        # the message. Escalate to a human.
        print(f"Claude API error: {e}")
        return {
            "message_id": normalised["message_id"],
            "query_type": normalised["query_type"],
            "drafted_reply": None,
            "confidence_score": 0.0,
            "action": "escalate",
            "error": "AI drafting failed - sent to human agent",
        }

    # Step 4: decide the action based on confidence and query type
    action = decide_action(confidence, normalised["query_type"])

    return {
        "message_id": normalised["message_id"],
        "query_type": normalised["query_type"],
        "drafted_reply": reply_text,
        "confidence_score": confidence,
        "action": action,
    }


def decide_action(confidence: float, query_type: str) -> str:
    """
    Maps confidence to action.
    Complaints always escalate - we don't let the AI auto-respond to angry guests.
    """
    if query_type == "complaint":
        return "escalate"
    if confidence >= 0.85:
        return "auto_send"
    if confidence >= 0.60:
        return "agent_review"
    return "escalate"
