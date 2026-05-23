from src.claude_client import draft_reply, WORKER_URL, PROXY_AUTH_TOKEN
from src.property_data import get_property_context

print("WORKER_URL:", WORKER_URL)
print("TOKEN (first 12):", str(PROXY_AUTH_TOKEN)[:12])
print("-" * 40)

ctx = get_property_context('villa-b1')
try:
    reply, conf = draft_reply('Test', 'what is the wifi password', 'post_sales_checkin', ctx)
    print('SUCCESS')
    print('Reply:', reply)
    print('Confidence:', conf)
except Exception as e:
    print('ERROR TYPE:', type(e).__name__)
    print('ERROR:', e)
