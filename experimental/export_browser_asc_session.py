#!/usr/bin/env python3

import argparse
import json
import pathlib
import sys

import browser_cookie3
import requests


def default_chrome_cookie_file(profile_name: str) -> pathlib.Path:
    return (
        pathlib.Path.home()
        / "Library"
        / "Application Support"
        / "Google"
        / "Chrome"
        / profile_name
        / "Cookies"
    )


def export_cookie_payload(cookie_file: pathlib.Path):
    jar = browser_cookie3.chrome(cookie_file=str(cookie_file), domain_name="apple.com")
    session = requests.Session()
    session.cookies.update(jar)
    response = session.get("https://appstoreconnect.apple.com/olympus/v1/session", timeout=30)
    response.raise_for_status()
    session_payload = response.json().get("data", {})
    provider = session_payload.get("provider", {}) or {}
    provider_id = provider.get("providerId") or session_payload.get("providerId")

    cookies = []
    for cookie in jar:
        domain = cookie.domain or ""
        if not domain.endswith("apple.com"):
            continue
        cookies.append(
            {
                "name": cookie.name,
                "value": cookie.value,
                "domain": domain,
                "path": cookie.path or "/",
                "secure": bool(cookie.secure),
                "expires": cookie.expires,
            }
        )

    return {
        "provider_id": provider_id,
        "email": session_payload.get("user", {}).get("emailAddress"),
        "cookies": cookies,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export ASC browser session cookies from a local Chrome profile."
    )
    parser.add_argument(
        "--profile-name",
        default="Profile 1",
        help="Chrome profile directory name under ~/Library/Application Support/Google/Chrome",
    )
    parser.add_argument(
        "--cookie-file",
        help="Explicit Chrome Cookies SQLite path. Overrides --profile-name.",
    )
    parser.add_argument("--output", required=True, help="Output JSON path.")
    args = parser.parse_args()

    cookie_file = pathlib.Path(args.cookie_file) if args.cookie_file else default_chrome_cookie_file(args.profile_name)
    if not cookie_file.exists():
        parser.error(f"Chrome cookie database not found: {cookie_file}")

    payload = export_cookie_payload(cookie_file)
    pathlib.Path(args.output).write_text(json.dumps(payload), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
