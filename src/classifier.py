"""
Classifies an incoming guest message into one of six query types.

This is a simple keyword-based classifier. In production you'd probably
use Claude itself for this, or a small fine-tuned model. But for the
first version, keywords get us 80% of the way there for almost no cost
and zero latency.
"""


# Keywords that strongly hint at each query type.
# Order matters: we check complaint first because an angry message about
# pricing should still be treated as a complaint.
KEYWORDS = {
    "complaint": [
        "not working", "broken", "unacceptable", "refund", "complaint",
        "terrible", "awful", "worst", "disappointed", "angry", "issue with",
        "problem with", "doesn't work", "no hot water", "no water",
        "no wifi", "ac not", "dirty",
    ],
    "pre_sales_availability": [
        "available", "availability", "free on", "open on", "book for",
        "vacant", "any dates",
    ],
    "pre_sales_pricing": [
        "rate", "price", "cost", "how much", "charges", "fees",
        "per night", "total cost",
    ],
    "post_sales_checkin": [
        "check in", "check-in", "checkin", "checkout", "check out",
        "wifi password", "wifi", "arrival time", "key", "address",
    ],
    "special_request": [
        "early check", "late check", "airport", "transfer", "pickup",
        "pick up", "chef", "extra bed", "decoration", "anniversary",
        "birthday", "can you arrange", "is it possible to",
    ],
}


def classify_query(message: str) -> str:
    """
    Returns one of: complaint, pre_sales_availability, pre_sales_pricing,
    post_sales_checkin, special_request, general_enquiry.
    """
    text = message.lower()

    # Check complaints first - they always win
    for word in KEYWORDS["complaint"]:
        if word in text:
            return "complaint"

    # Then check everything else in order
    for query_type in [
        "pre_sales_availability",
        "pre_sales_pricing",
        "post_sales_checkin",
        "special_request",
    ]:
        for word in KEYWORDS[query_type]:
            if word in text:
                return query_type

    # Default bucket for anything we can't classify
    return "general_enquiry"
