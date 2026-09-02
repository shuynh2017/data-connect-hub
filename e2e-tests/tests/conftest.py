"""Shared configuration and fixtures for DCH e2e tests."""

from __future__ import annotations

import contextlib
import os
import subprocess
import uuid
from collections.abc import Iterator
from urllib.parse import urlparse

import httpx
import pytest

from data_connect_hub import CredentialsRef, DataConnectClient

REST_RBAC_PROXY_API_BASE = os.environ.get(
    "REST_RBAC_PROXY_API_BASE", "https://localhost:18443/api/v1alpha1/data"
)
REST_API_BASE = os.environ.get(
    "REST_API_BASE", "http://localhost:18080/api/v1alpha1/data"
)
TENANT_A_NS = os.environ.get("TENANT_A_NS", "tenant-a")
TENANT_A_DCH_USER = os.environ.get("TENANT_A_DCH_USER", "dch-user")
TENANT_A_DCH_ADMIN = os.environ.get("TENANT_A_DCH_ADMIN", "dch-admin")
TENANT_A_NONE_DCH_USER = os.environ.get("TENANT_A_NONE_DCH_USER", "dch-none-user")
NO_ACCESS_NAMESPACE = os.environ.get("DCH_NO_ACCESS_NAMESPACE", "tenant-b")
TOKEN_AUDIENCE = os.environ.get("DCH_TOKEN_AUDIENCE", "https://kubernetes.default.svc")


def service_account_token(
    service_account: str,
    namespace: str = TENANT_A_NS,
    audience: str = TOKEN_AUDIENCE,
) -> str | None:
    """Return a short-lived bearer token for a ServiceAccount, or None if it cannot be created."""
    try:
        result = subprocess.run(
            [
                "kubectl",
                "create",
                "token",
                service_account,
                "-n",
                namespace,
                "--audience",
                audience,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return result.stdout.strip() or None


@pytest.fixture(scope="session")
def rbac_proxy_base() -> str:
    """Base URL of the rest-service behind the kube-rbac-proxy."""
    return REST_RBAC_PROXY_API_BASE


@pytest.fixture(scope="session")
def rest_base() -> str:
    """Base URL of the rest-service accessed directly (no rbac-proxy)."""
    return REST_API_BASE


@pytest.fixture(scope="session")
def rest_root() -> str:
    """Root URL (scheme://host:port) of the rest-service, for non-scoped routes like /health."""
    parsed = urlparse(REST_API_BASE)
    return f"{parsed.scheme}://{parsed.netloc}"


@pytest.fixture(scope="session")
def tenant_ns() -> str:
    """Namespace used as the tenant for RBAC tests."""
    return TENANT_A_NS


@pytest.fixture(scope="session")
def no_access_namespace() -> str:
    """A tenant namespace the read-only user has no RBAC role binding in."""
    return NO_ACCESS_NAMESPACE


@pytest.fixture(scope="session")
def dch_user_token() -> str:
    """Bearer token for the read-only tenant ServiceAccount."""
    token = os.environ.get("DCH_USER_TOKEN") or service_account_token(TENANT_A_DCH_USER)
    if not token:
        pytest.skip("no DCH user token available (set DCH_USER_TOKEN or ensure kubectl access)")
    return token


@pytest.fixture(scope="session")
def dch_admin_token() -> str:
    """Bearer token for the read-write tenant ServiceAccount."""
    token = os.environ.get("DCH_ADMIN_TOKEN") or service_account_token(TENANT_A_DCH_ADMIN)
    if not token:
        pytest.skip("no DCH admin token available (set DCH_ADMIN_TOKEN or ensure kubectl access)")
    return token

@pytest.fixture(scope="session")
def dch_none_user_token() -> str:
    """Bearer token for a tenant ServiceAccount with no RBAC role binding."""
    token = os.environ.get("DCH_NONE_USER_TOKEN") or service_account_token(TENANT_A_NONE_DCH_USER)
    if not token:
        pytest.skip("no DCH none user token available (set DCH_NONE_USER_TOKEN or ensure kubectl access)")
    return token

@pytest.fixture
def http_client() -> Iterator[httpx.Client]:
    """An httpx client that does not verify TLS (rbac-proxy uses a self-signed cert)."""
    with httpx.Client(verify=False) as client:
        yield client


@pytest.fixture(scope="session")
def gateway_endpoint() -> str:
    """Gateway host:port the SDK targets, derived from the rbac-proxy base URL."""
    return urlparse(REST_RBAC_PROXY_API_BASE).netloc


@pytest.fixture(scope="session")
def rest_client(
    gateway_endpoint: str,
    dch_admin_token: str,
    tenant_ns: str,
) -> Iterator[DataConnectClient]:
    """SDK client authenticated as the read-write tenant admin, through the rbac-proxy."""
    client = DataConnectClient(
        gateway_endpoint,
        token=dch_admin_token,
        tenant_id=tenant_ns,
        insecure=True,
        max_retries=1,
        rest_timeout=15.0,
    )
    yield client
    client.close()


def _unique_name(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:8]}"


@pytest.fixture
def create_connection_type(rest_client: DataConnectClient):
    """Factory: creates connection types, deletes them after the test."""
    created_ids: list[str] = []

    def _factory(
        *,
        name: str | None = None,
        provider: str = "postgres",
        description: str | None = "e2e test connection type",
    ):
        ct = rest_client.create_connection_type(
            name=name or _unique_name("e2e-ct"),
            provider=provider,
            description=description,
        )
        created_ids.append(ct.id)
        return ct

    yield _factory

    for ct_id in reversed(created_ids):
        with contextlib.suppress(Exception):
            rest_client.delete_connection_type(ct_id)


@pytest.fixture
def create_connection(rest_client: DataConnectClient):
    """Factory: creates connections, deletes them after the test."""
    created_ids: list[str] = []

    def _factory(
        *,
        name: str | None = None,
        connection_type_id: str,
        data_format: str = "tabular",
        credentials_ref: CredentialsRef | None = None,
        properties: dict[str, str] | None = None,
    ):
        conn = rest_client.create_connection(
            name=name or _unique_name("e2e-conn"),
            connection_type_id=connection_type_id,
            data_format=data_format,
            credentials_ref=credentials_ref,
            properties=properties,
        )
        created_ids.append(conn.id)
        return conn

    yield _factory

    for conn_id in reversed(created_ids):
        with contextlib.suppress(Exception):
            rest_client.delete_connection(conn_id)
