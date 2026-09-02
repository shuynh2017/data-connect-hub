"""Smoke tests: verify the DCH operator deployment."""

from __future__ import annotations

import json
import os
import subprocess

import pytest



class TestDCHService:
    def test_dataconnectservice_ready(self) -> None:
        namespace = os.environ.get("DCH_SERVICE_NAMESPACE")
        if not namespace:
            pytest.skip("DCH_SERVICE_NAMESPACE not set")
        name = os.environ.get("DCH_SERVICE_NAME")
        if not name:
            pytest.skip("DCH_SERVICE_NAME not set")

        print(f"\nTesting: DataConnectService CR {namespace}/{name}")
        print("Expected: phase is Ready")

        result = subprocess.run(
            [
                "kubectl",
                "get",
                "dataconnectservice",
                name,
                "-n",
                namespace,
                "-o",
                "jsonpath={.status.phase}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        phase = result.stdout.strip()
        assert phase == "Ready", (
            f"DataConnectService {namespace}/{name} phase is {phase!r}, expected 'Ready'"
        )
