"""Smoke tests: verify the DCH operator deployment."""

from __future__ import annotations

import json
import os
import subprocess

import pytest

EXPECTED_OPERATOR_IMAGE = (
    "quay.io/opendatahub/odh-data-connect-hub-controller:odh-stable"
)


class TestDCHOperator:
    def test_operator_image(self) -> None:
        print(f"\nTesting: DCH operator image deployment {os.environ.get('DCH_OPERATOR_NAMESPACE')}/{os.environ.get('DCH_OPERATOR_DEPLOYMENT')}")
        print(f"Expected: Official image {EXPECTED_OPERATOR_IMAGE}")
        namespace = os.environ.get("DCH_OPERATOR_NAMESPACE")
        if not namespace:
            pytest.skip("DCH_OPERATOR_NAMESPACE not set")
        deployment = os.environ.get("DCH_OPERATOR_DEPLOYMENT")
        if not deployment:
            pytest.skip("DCH_OPERATOR_DEPLOYMENT not set")

        result = subprocess.run(
            [
                "kubectl",
                "get",
                "deployment",
                deployment,
                "-n",
                namespace,
                "-o",
                "jsonpath={.spec.template.spec.containers[*].image}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        images = result.stdout.split()
        assert EXPECTED_OPERATOR_IMAGE in images, (
            f"operator image {EXPECTED_OPERATOR_IMAGE} not found in {images}"
        )

    def test_operator_pod_running(self) -> None:
        print(f"\nTesting: DCH operator pod is running ")
        print(f"Expected: All operator pods are in Running phase")
        namespace = os.environ.get("DCH_OPERATOR_NAMESPACE")
        if not namespace:
            pytest.skip("DCH_OPERATOR_NAMESPACE not set")
        deployment = os.environ.get("DCH_OPERATOR_DEPLOYMENT")
        if not deployment:
            pytest.skip("DCH_OPERATOR_DEPLOYMENT not set")

        labels = subprocess.run(
            [
                "kubectl",
                "get",
                "deployment",
                deployment,
                "-n",
                namespace,
                "-o",
                "jsonpath={.spec.selector.matchLabels}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        match_labels: dict[str, str] = json.loads(labels.stdout)
        label_selector = ",".join(f"{k}={v}" for k, v in match_labels.items())

        result = subprocess.run(
            [
                "kubectl",
                "get",
                "pods",
                "-n",
                namespace,
                "-l",
                label_selector,
                "-o",
                "jsonpath={.items[*].status.phase}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        phases = result.stdout.split()
        assert phases, f"no operator pods found for selector {label_selector}"
        assert all(phase == "Running" for phase in phases), (
            f"operator pod(s) not running: {phases}"
        )

    def test_operator_not_crashing(self) -> None:
        print("\nTesting: DCH operator pod is not crashing")
        print("Expected: No CrashLoopBackOff and low container restart counts")
        namespace = os.environ.get("DCH_OPERATOR_NAMESPACE")
        if not namespace:
            pytest.skip("DCH_OPERATOR_NAMESPACE not set")
        deployment = os.environ.get("DCH_OPERATOR_DEPLOYMENT")
        if not deployment:
            pytest.skip("DCH_OPERATOR_DEPLOYMENT not set")

        labels = subprocess.run(
            [
                "kubectl",
                "get",
                "deployment",
                deployment,
                "-n",
                namespace,
                "-o",
                "jsonpath={.spec.selector.matchLabels}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        match_labels: dict[str, str] = json.loads(labels.stdout)
        label_selector = ",".join(f"{k}={v}" for k, v in match_labels.items())

        result = subprocess.run(
            [
                "kubectl",
                "get",
                "pods",
                "-n",
                namespace,
                "-l",
                label_selector,
                "-o",
                "json",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        pods = json.loads(result.stdout).get("items", [])
        assert pods, f"no operator pods found for selector {label_selector}"

        for pod in pods:
            pod_name = pod["metadata"]["name"]
            for cs in pod.get("status", {}).get("containerStatuses", []):
                waiting = cs.get("state", {}).get("waiting", {})
                assert waiting.get("reason") != "CrashLoopBackOff", (
                    f"container {cs['name']} in pod {pod_name} is in CrashLoopBackOff: "
                    f"{waiting.get('message')}"
                )
                assert cs.get("restartCount", 0) == 0, (
                    f"container {cs['name']} in pod {pod_name} has restarted "
                    f"{cs['restartCount']} time(s)"
                )
