"""
Mock property data. In a real system this would come from PostgreSQL,
pulled live so changes to rates or availability are picked up instantly.
"""


PROPERTIES = {
    "villa-b1": {
        "name": "Villa B1",
        "location": "Assagao, North Goa",
        "bedrooms": 3,
        "max_guests": 6,
        "private_pool": True,
        "check_in_time": "2pm",
        "check_out_time": "11am",
        "base_rate_inr": 18000,
        "base_rate_covers_guests": 4,
        "extra_guest_charge_inr": 2000,
        "wifi_password": "Nistula@2024",
        "caretaker_hours": "8am to 10pm",
        "chef_on_call": "Yes, pre-booking required",
        "availability_apr_20_24": "Available",
        "cancellation": "Free up to 7 days before check-in",
    }
}


def get_property_context(property_id: str) -> str | None:
    """
    Returns a formatted string version of the property details, ready to
    drop into a Claude prompt. Returns None if the property doesn't exist.
    """
    prop = PROPERTIES.get(property_id)
    if prop is None:
        return None

    return f"""
Property: {prop['name']}, {prop['location']}
Bedrooms: {prop['bedrooms']} | Max guests: {prop['max_guests']} | Private pool: {'Yes' if prop['private_pool'] else 'No'}
Check-in: {prop['check_in_time']} | Check-out: {prop['check_out_time']}
Base rate: INR {prop['base_rate_inr']:,} per night (up to {prop['base_rate_covers_guests']} guests)
Extra guest: INR {prop['extra_guest_charge_inr']:,} per night per person
WiFi password: {prop['wifi_password']}
Caretaker: Available {prop['caretaker_hours']}
Chef on call: {prop['chef_on_call']}
Availability April 20-24: {prop['availability_apr_20_24']}
Cancellation: {prop['cancellation']}
""".strip()
