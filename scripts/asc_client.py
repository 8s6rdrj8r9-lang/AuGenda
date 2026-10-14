#!/usr/bin/env python3
"""
App Store Connect REST API Client & Binary Uploader
EnsDev Apple Platform Standard v1.0 Automation Tool

Supports:
- Generating ES256 JWT tokens
- Listing registered apps & builds
- Creating build uploads (POST /v1/buildUploads)
- Registering binary files (POST /v1/buildUploadFiles)
- Chunked multi-part uploading to Apple object storage
- Committing build uploads (PATCH /v1/buildUploadFiles/{id})
"""

import os
import sys
import time
import argparse
import json
import mimetypes
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=Warning)

try:
    import jwt
    import requests
except ImportError:
    print("Error: Required dependencies missing. Run: pip3 install pyjwt cryptography requests")
    sys.exit(1)

# Default configuration from EnsDev environment
DEFAULT_KEY_ID = "926KT9XJP6"
DEFAULT_ISSUER_ID = "46ad235f-06a2-480b-a355-05ea6183c37d"
DEFAULT_KEY_PATHS = [
    Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{DEFAULT_KEY_ID}.p8",
    Path.home() / ".private_keys" / f"AuthKey_{DEFAULT_KEY_ID}.p8",
    Path.home() / "Downloads" / f"AuthKey_{DEFAULT_KEY_ID}.p8",
]

API_BASE = "https://api.appstoreconnect.apple.com/v1"

class AppStoreConnectClient:
    def __init__(self, key_id=None, issuer_id=None, key_path=None):
        self.key_id = key_id or os.environ.get("ASC_KEY_ID", DEFAULT_KEY_ID)
        self.issuer_id = issuer_id or os.environ.get("ASC_ISSUER_ID", DEFAULT_ISSUER_ID)
        
        search_paths = [
            Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{self.key_id}.p8",
            Path.home() / ".private_keys" / f"AuthKey_{self.key_id}.p8",
            Path.home() / "Downloads" / f"AuthKey_{self.key_id}.p8",
        ]
        
        resolved_path = None
        if key_path and Path(key_path).exists():
            resolved_path = Path(key_path)
        else:
            for p in search_paths:
                if p.exists():
                    resolved_path = p
                    break
                    
        if not resolved_path:
            raise FileNotFoundError(f"Could not locate AuthKey_{self.key_id}.p8 in standard search paths.")
            
        self.key_path = resolved_path
        with open(self.key_path, "r") as f:
            self.private_key = f.read()

    def generate_token(self, exp_minutes=20) -> str:
        """Generate ES256 JWT valid for exp_minutes (max 20 min)."""
        now = int(time.time())
        payload = {
            "iss": self.issuer_id,
            "iat": now,
            "exp": now + (exp_minutes * 60),
            "aud": "appstoreconnect-v1"
        }
        headers = {
            "alg": "ES256",
            "kid": self.key_id,
            "typ": "JWT"
        }
        return jwt.encode(payload, self.private_key, algorithm="ES256", headers=headers)

    def _request(self, method: str, endpoint: str, json_data=None, timeout=30):
        token = self.generate_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
        url = f"{API_BASE}{endpoint}" if endpoint.startswith("/") else endpoint
        resp = requests.request(method, url, headers=headers, json=json_data, timeout=timeout)
        return resp

    def list_apps(self):
        """Query GET /v1/apps to list all registered apps."""
        resp = self._request("GET", "/apps")
        if resp.status_code != 200:
            print(f"Error fetching apps ({resp.status_code}): {resp.text}")
            return []
        data = resp.json().get("data", [])
        return [
            {
                "id": app["id"],
                "name": app["attributes"].get("name"),
                "bundleId": app["attributes"].get("bundleId"),
                "sku": app["attributes"].get("sku"),
                "primaryLocale": app["attributes"].get("primaryLocale"),
            }
            for app in data
        ]

    def list_builds(self, app_id=None):
        """Query GET /v1/builds, optionally filtered by app_id."""
        url = f"/builds?filter[app]={app_id}" if app_id else "/builds"
        resp = self._request("GET", url)
        if resp.status_code != 200:
            print(f"Error fetching builds ({resp.status_code}): {resp.text}")
            return []
        data = resp.json().get("data", [])
        return [
            {
                "id": b["id"],
                "version": b["attributes"].get("version"),
                "uploadedDate": b["attributes"].get("uploadedDate"),
                "processingState": b["attributes"].get("processingState"),
                "minOsVersion": b["attributes"].get("minOsVersion"),
            }
            for b in data
        ]

    def upload_binary(self, app_id: str, file_path: str, version: str, build_number: str, platform: str):
        """
        Upload binary (.ipa or .pkg) via POST /v1/buildUploads and POST /v1/buildUploadFiles.
        platform: 'IOS' or 'MAC_OS'
        """
        p = Path(file_path)
        if not p.exists():
            raise FileNotFoundError(f"Binary file not found: {file_path}")
            
        file_size = p.stat().st_size
        file_name = p.name
        suffix = p.suffix.lower()
        
        if suffix == ".ipa":
            uti = "com.apple.ipa"
            if not platform:
                platform = "IOS"
        elif suffix in [".pkg", ".dmg"]:
            uti = "com.apple.pkg"
            if not platform:
                platform = "MAC_OS"
        elif suffix == ".zip":
            uti = "com.pkware.zip-archive"
        else:
            raise ValueError(f"Unsupported binary format '{suffix}'. Expected .ipa, .pkg, or .zip.")

        print(f"\n[1/4] Creating Build Upload container on App Store Connect...")
        print(f"      App ID: {app_id} | Version: {version} ({build_number}) | Platform: {platform}")
        
        build_upload_payload = {
            "data": {
                "type": "buildUploads",
                "attributes": {
                    "cfBundleShortVersionString": str(version),
                    "cfBundleVersion": str(build_number),
                    "platform": platform.upper()
                },
                "relationships": {
                    "app": {
                        "data": {
                            "type": "apps",
                            "id": str(app_id)
                        }
                    }
                }
            }
        }
        resp = self._request("POST", "/buildUploads", json_data=build_upload_payload)
        if resp.status_code != 201:
            raise RuntimeError(f"Failed to create build upload ({resp.status_code}): {resp.text}")
            
        upload_data = resp.json()["data"]
        upload_id = upload_data["id"]
        print(f"      Build Upload ID created: {upload_id}")

        print(f"\n[2/4] Registering binary file reservation...")
        print(f"      File: {file_name} ({file_size} bytes, UTI: {uti})")
        
        file_reg_payload = {
            "data": {
                "type": "buildUploadFiles",
                "attributes": {
                    "assetType": "ASSET",
                    "fileName": file_name,
                    "fileSize": file_size,
                    "uti": uti
                },
                "relationships": {
                    "buildUpload": {
                        "data": {
                            "type": "buildUploads",
                            "id": upload_id
                        }
                    }
                }
            }
        }
        resp = self._request("POST", "/buildUploadFiles", json_data=file_reg_payload)
        if resp.status_code != 201:
            raise RuntimeError(f"Failed to register build upload file ({resp.status_code}): {resp.text}")
            
        file_data = resp.json()["data"]
        file_id = file_data["id"]
        upload_ops = file_data["attributes"].get("uploadOperations", [])
        print(f"      File ID registered: {file_id}")
        print(f"      Received {len(upload_ops)} chunk upload operations from Apple.")

        print(f"\n[3/4] Uploading binary chunks directly to Apple Object Storage...")
        with open(p, "rb") as bf:
            for idx, op in enumerate(upload_ops, start=1):
                url = op["url"]
                length = op["length"]
                offset = op["offset"]
                method = op.get("method", "PUT")
                req_headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
                
                bf.seek(offset)
                chunk_data = bf.read(length)
                
                print(f"      Uploading chunk {idx}/{len(upload_ops)}: offset {offset}, {length} bytes...")
                put_resp = requests.request(method, url, headers=req_headers, data=chunk_data, timeout=120)
                if put_resp.status_code not in [200, 201, 204]:
                    raise RuntimeError(f"Chunk {idx} upload failed ({put_resp.status_code}): {put_resp.text}")
                    
        print(f"      All chunks successfully streamed to Apple storage.")

        print(f"\n[4/4] Committing build upload to initiate App Store Connect processing...")
        commit_payload = {
            "data": {
                "type": "buildUploadFiles",
                "id": file_id,
                "attributes": {
                    "uploaded": True
                }
            }
        }
        resp = self._request("PATCH", f"/buildUploadFiles/{file_id}", json_data=commit_payload)
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to commit build upload ({resp.status_code}): {resp.text}")

        print(f"      Build upload committed successfully!")
        print(f"      Status: PROCESSING. Apple backend is preparing the build for TestFlight.")
        return resp.json()["data"]


def main():
    parser = argparse.ArgumentParser(description="App Store Connect API CLI - EnsDev Distribution")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Subcommand: list-apps
    subparsers.add_parser("list-apps", help="List all registered apps and their App Store IDs")

    # Subcommand: list-builds
    builds_parser = subparsers.add_parser("list-builds", help="List builds for an app")
    builds_parser.add_argument("--app-id", help="App ID to filter builds (optional)")

    # Subcommand: upload
    upload_parser = subparsers.add_parser("upload", help="Upload an .ipa or .pkg binary to App Store Connect")
    upload_parser.add_argument("--app-id", required=True, help="App Store Connect App ID (e.g. 6822482233)")
    upload_parser.add_argument("--file", required=True, help="Path to .ipa or .pkg binary")
    upload_parser.add_argument("--version", required=True, help="Version string (e.g. 1.0.0)")
    upload_parser.add_argument("--build", required=True, help="Build number (e.g. 1)")
    upload_parser.add_argument("--platform", choices=["IOS", "MAC_OS"], help="Platform (IOS or MAC_OS)")

    args = parser.parse_args()
    client = AppStoreConnectClient()

    if args.command == "list-apps":
        apps = client.list_apps()
        print(f"\n{'ID':<14} | {'Name':<12} | {'Bundle ID':<22} | {'SKU':<16} | Locale")
        print("-" * 75)
        for a in apps:
            print(f"{a['id']:<14} | {a['name']:<12} | {a['bundleId']:<22} | {a['sku']:<16} | {a['primaryLocale']}")
        print()

    elif args.command == "list-builds":
        builds = client.list_builds(args.app_id)
        print(f"\nFound {len(builds)} builds:")
        for b in builds:
            print(f"ID: {b['id']} | Version: {b['version']} | State: {b['processingState']} | Uploaded: {b['uploadedDate']}")
        print()

    elif args.command == "upload":
        client.upload_binary(
            app_id=args.app_id,
            file_path=args.file,
            version=args.version,
            build_number=args.build,
            platform=args.platform
        )

if __name__ == "__main__":
    main()
