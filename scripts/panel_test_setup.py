#!/usr/bin/env python3
"""
Setup test user and subscription on Remnawave panel for Commy integration testing.

Usage:
    python scripts/panel_test_setup.py --setup    # Create test user and get subscription
    python scripts/panel_test_setup.py --cleanup   # Delete test user
    python scripts/panel_test_setup.py --get-link  # Get subscription link only
"""

import os
import sys
import json
import argparse
import base64
from pathlib import Path
from dotenv import load_dotenv
import httpx

# Load .env.local
env_path = Path(__file__).parent.parent / ".env.local"
if env_path.exists():
    load_dotenv(env_path)
else:
    print(f"❌ Error: {env_path} not found. Copy from .env.example and fill in credentials.")
    sys.exit(1)

PANEL_URL = os.getenv("PANEL_URL")
PANEL_API_KEY = os.getenv("PANEL_API_KEY")
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL")
TEST_USER_TRAFFIC_LIMIT_GB = int(os.getenv("TEST_USER_TRAFFIC_LIMIT_GB", "100"))

if not all([PANEL_URL, PANEL_API_KEY, TEST_USER_EMAIL]):
    print("❌ Error: PANEL_URL, PANEL_API_KEY, TEST_USER_EMAIL must be set in .env.local")
    sys.exit(1)


class PanelAPI:
    def __init__(self, base_url: str, api_key: str):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.client = httpx.Client(
            base_url=self.base_url,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=30.0,
        )

    def create_user(self, email: str, traffic_limit_gb: int = 100) -> dict:
        """Create a new user on the panel."""
        print(f"📝 Creating test user: {email}")

        payload = {
            "email": email,
            "traffic_limit_gb": traffic_limit_gb,
            "expire_days": 365,  # Valid for a year
        }

        try:
            resp = self.client.post("/api/users", json=payload)
            resp.raise_for_status()
            user = resp.json()
            print(f"✅ User created: {user.get('id')} ({user.get('email')})")
            return user
        except httpx.HTTPStatusError as e:
            print(f"❌ Failed to create user: {e.status_code} {e.response.text}")
            raise

    def get_user_subscription(self, user_id: str) -> str:
        """Get subscription link for a user."""
        print(f"🔗 Fetching subscription link for user {user_id}")

        try:
            resp = self.client.get(f"/api/users/{user_id}/subscription")
            resp.raise_for_status()
            data = resp.json()

            sub_link = data.get("subscription_link") or data.get("link")
            if not sub_link:
                print("❌ No subscription link in response:", data)
                raise ValueError("Subscription link not found")

            return sub_link
        except httpx.HTTPStatusError as e:
            print(f"❌ Failed to get subscription: {e.status_code} {e.response.text}")
            raise

    def delete_user(self, user_id: str) -> None:
        """Delete a user from the panel."""
        print(f"🗑️  Deleting user: {user_id}")

        try:
            resp = self.client.delete(f"/api/users/{user_id}")
            resp.raise_for_status()
            print(f"✅ User deleted: {user_id}")
        except httpx.HTTPStatusError as e:
            print(f"❌ Failed to delete user: {e.status_code} {e.response.text}")
            raise

    def close(self):
        self.client.close()


def save_subscription(email: str, sub_link: str):
    """Save subscription details to a local file for the app to use."""
    output_dir = Path(__file__).parent.parent / "test_fixtures"
    output_dir.mkdir(exist_ok=True)

    output_file = output_dir / "test_subscription.private.json"

    data = {
        "email": email,
        "subscription_url": sub_link,
        "created_at": "2026-09-09T00:00:00Z",
        "note": "Test subscription for Commy. DO NOT COMMIT.",
    }

    with open(output_file, "w") as f:
        json.dump(data, f, indent=2)

    print(f"💾 Saved to: {output_file}")
    return output_file


def main():
    parser = argparse.ArgumentParser(description="Setup Commy test environment")
    parser.add_argument("--setup", action="store_true", help="Create test user and subscription")
    parser.add_argument("--cleanup", action="store_true", help="Delete test user")
    parser.add_argument("--get-link", action="store_true", help="Get subscription link only")
    parser.add_argument("--user-id", help="Specific user ID for --get-link")

    args = parser.parse_args()

    if not (args.setup or args.cleanup or args.get_link):
        parser.print_help()
        return

    api = PanelAPI(PANEL_URL, PANEL_API_KEY)

    try:
        if args.setup:
            # Create user
            user = api.create_user(TEST_USER_EMAIL, TEST_USER_TRAFFIC_LIMIT_GB)
            user_id = user["id"]

            # Get subscription
            sub_link = api.get_user_subscription(user_id)
            print(f"\n📋 Subscription URL:\n{sub_link}\n")

            # Save to file
            output_file = save_subscription(TEST_USER_EMAIL, sub_link)

            print(f"\n✨ Setup complete!")
            print(f"   User ID: {user_id}")
            print(f"   Email: {TEST_USER_EMAIL}")
            print(f"   Subscription saved to: {output_file}")
            print(f"\n💡 Next steps:")
            print(f"   1. Copy the subscription URL above into Commy app")
            print(f"   2. Or run: python scripts/panel_test_setup.py --cleanup --user-id {user_id}")

        elif args.cleanup:
            if not args.user_id:
                print("❌ Error: --user-id required for --cleanup")
                sys.exit(1)
            api.delete_user(args.user_id)

            # Try to remove saved file
            output_file = Path(__file__).parent.parent / "test_fixtures" / "test_subscription.private.json"
            if output_file.exists():
                output_file.unlink()
                print(f"   Removed: {output_file}")

        elif args.get_link:
            if not args.user_id:
                print("❌ Error: --user-id required for --get-link")
                sys.exit(1)
            sub_link = api.get_user_subscription(args.user_id)
            print(f"\n📋 Subscription URL:\n{sub_link}\n")

    finally:
        api.close()


if __name__ == "__main__":
    main()
