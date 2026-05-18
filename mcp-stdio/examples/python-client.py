"""Minimal Python client for the deephermes REST API.

Usage:
    export DEEPHERMES_API_BASE=http://localhost:8080
    export DEEPHERMES_API_KEY=<one of the API_KEYS from rest-api/.env>
    python python-client.py
"""
import os
import sys
import requests

API_BASE = os.environ.get("DEEPHERMES_API_BASE", "http://localhost:8080")
API_KEY = os.environ.get("DEEPHERMES_API_KEY")

if not API_KEY:
    sys.exit("Set DEEPHERMES_API_KEY")


def chat(prompt: str, model: str = "deepseek-chat") -> str:
    r = requests.post(
        f"{API_BASE}/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
        json={"model": model, "messages": [{"role": "user", "content": prompt}]},
        timeout=60,
    )
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


if __name__ == "__main__":
    print(chat("What is the capital of France? One word."))
