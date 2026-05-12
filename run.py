"""
Run script. Loads .env then starts the server.

Use: python run.py
Or:  uvicorn src.main:app --reload
"""

from dotenv import load_dotenv
load_dotenv()

import uvicorn
from src.main import app


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
