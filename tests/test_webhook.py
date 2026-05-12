"""
Manual test script. Hits the local webhook with five different message
types and prints the responses.

Run the server first: python run.py
Then in another terminal: python tests/test_webhook.py
"""

import json
import requests


URL = "http://localhost:8000/webhook/message"


# Five test cases covering different query types and edge cases
TEST_CASES = [
    {
        "name": "Pre-sales availability (the example from the brief)",
        "payload": {
            "source": "whatsapp",
            "guest_name": "Rahul Sharma",
            "message": "Is the villa available from April 20 to 24? What is the rate for 2 adults?",
            "timestamp": "2026-05-05T10:30:00Z",
            "booking_ref": "NIS-2024-0891",
            "property_id": "villa-b1",
        },
    },
    {
        "name": "Post-sales WiFi question",
        "payload": {
            "source": "whatsapp",
            "guest_name": "Priya Menon",
            "message": "Hi, what is the wifi password please?",
            "timestamp": "2026-05-05T14:00:00Z",
            "booking_ref": "NIS-2024-0902",
            "property_id": "villa-b1",
        },
    },
    {
        "name": "Special request - early check-in",
        "payload": {
            "source": "airbnb",
            "guest_name": "James Wilson",
            "message": "We arrive at 11am on Saturday. Is early check-in possible?",
            "timestamp": "2026-05-05T09:00:00Z",
            "booking_ref": "NIS-2024-0915",
            "property_id": "villa-b1",
        },
    },
    {
        "name": "Complaint - should always escalate",
        "payload": {
            "source": "whatsapp",
            "guest_name": "Anita Desai",
            "message": "The AC in the master bedroom is not working. This is unacceptable.",
            "timestamp": "2026-05-05T23:30:00Z",
            "booking_ref": "NIS-2024-0921",
            "property_id": "villa-b1",
        },
    },
    {
        "name": "General enquiry - pets",
        "payload": {
            "source": "instagram",
            "guest_name": "Kabir Khan",
            "message": "Do you allow pets at the villa?",
            "timestamp": "2026-05-05T11:15:00Z",
            "booking_ref": None,
            "property_id": "villa-b1",
        },
    },
]


def run_tests():
    for i, case in enumerate(TEST_CASES, 1):
        print(f"\n{'=' * 60}")
        print(f"TEST {i}: {case['name']}")
        print(f"{'=' * 60}")
        print(f"Message: {case['payload']['message']}")

        try:
            response = requests.post(URL, json=case["payload"], timeout=30)
            data = response.json()
            print(f"\nStatus: {response.status_code}")
            print(f"Query type: {data.get('query_type')}")
            print(f"Confidence: {data.get('confidence_score')}")
            print(f"Action: {data.get('action')}")
            print(f"\nDrafted reply:")
            print(f"  {data.get('drafted_reply')}")
        except requests.exceptions.RequestException as e:
            print(f"\nERROR: {e}")
            print("Is the server running? Start it with: python run.py")


if __name__ == "__main__":
    run_tests()
