"""Smoke tests: verify the rbac-proxy and rest-service auth behavior."""

from __future__ import annotations

import httpx


class TestAuth:
    def test_rbac_proxy_read_user_authorized(
        self,
        http_client: httpx.Client,
        rbac_proxy_base: str,
        tenant_ns: str,
        dch_user_token: str,
    ) -> None:
        print(
            f"\nTesting: rbac-proxy allows read user for tenant '{tenant_ns}' at {rbac_proxy_base}"
        )
        print("Expected: HTTP 200 OK")

        headers = {
            "Authorization": f"Bearer {dch_user_token}",
            "X-Tenant-Id": tenant_ns,
        }
        response = http_client.get(f"{rbac_proxy_base}/connection-types", headers=headers)

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code == 200, (
            f"expected HTTP 200, got {response.status_code}: {response.text}"
        )

    def test_rbac_proxy_admin_user_authorized(
        self,
        http_client: httpx.Client,
        rbac_proxy_base: str,
        tenant_ns: str,
        dch_admin_token: str,
    ) -> None:
        print(
            f"\nTesting: rbac-proxy allows admin user for tenant '{tenant_ns}' at {rbac_proxy_base}"
        )
        print("Expected: HTTP 200 OK")

        headers = {
            "Authorization": f"Bearer {dch_admin_token}",
            "X-Tenant-Id": tenant_ns,
        }
        response = http_client.get(f"{rbac_proxy_base}/connection-types", headers=headers)

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code == 200, (
            f"expected HTTP 200, got {response.status_code}: {response.text}"
        )

    def test_rbac_proxy_none_user_authenticated_but_forbidden(
        self,
        http_client: httpx.Client,
        rbac_proxy_base: str,
        tenant_ns: str,
        dch_none_user_token: str,
    ) -> None:
        print(
            f"\nTesting: rbac-proxy authenticates a user with no role binding for tenant '{tenant_ns}' at {rbac_proxy_base}"
        )
        print("Expected: HTTP 403 Forbidden (authenticated, not rejected, but not authorized)")

        headers = {
            "Authorization": f"Bearer {dch_none_user_token}",
            "X-Tenant-Id": tenant_ns,
        }
        response = http_client.get(f"{rbac_proxy_base}/connection-types", headers=headers)

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code != 401, (
            f"token should be authenticated (not rejected), got {response.status_code}: {response.text}"
        )
        assert response.status_code == 403, (
            f"expected HTTP 403, got {response.status_code}: {response.text}"
        )

    def test_rbac_proxy_wrong_namespace_forbidden(
        self,
        http_client: httpx.Client,
        rbac_proxy_base: str,
        no_access_namespace: str,
        dch_user_token: str,
    ) -> None:
        print(
            f"\nTesting: rbac-proxy denies read user for a namespace it cannot access '{no_access_namespace}' at {rbac_proxy_base}"
        )
        print("Expected: HTTP 403 Forbidden")

        headers = {
            "Authorization": f"Bearer {dch_user_token}",
            "X-Tenant-Id": no_access_namespace,
        }
        response = http_client.get(f"{rbac_proxy_base}/connection-types", headers=headers)

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code == 403, (
            f"expected HTTP 403, got {response.status_code}: {response.text}"
        )

    def test_rbac_proxy_missing_tenant_bad_request(
        self,
        http_client: httpx.Client,
        rbac_proxy_base: str,
        dch_user_token: str,
    ) -> None:
        print(
            f"\nTesting: rbac-proxy rejects request with no x-tenant-id header at {rbac_proxy_base}"
        )
        print("Expected: HTTP 400 Bad Request")

        headers = {"Authorization": f"Bearer {dch_user_token}"}
        response = http_client.get(f"{rbac_proxy_base}/connection-types", headers=headers)

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code == 400, (
            f"expected HTTP 400, got {response.status_code}: {response.text}"
        )

    def test_rbac_proxy_user_no_token(
        self, http_client: httpx.Client, rbac_proxy_base: str
    ) -> None:
        print(f"\nTesting: rbac-proxy rejects request with no token at {rbac_proxy_base}")
        print("Expected: HTTP 401 Unauthorized")

        response = http_client.get(f"{rbac_proxy_base}/connection-types")

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code == 401, (
            f"expected HTTP 401, got {response.status_code}: {response.text}"
        )

    def test_rbac_proxy_user_bad_token(
        self, http_client: httpx.Client, rbac_proxy_base: str
    ) -> None:
        print(f"\nTesting: rbac-proxy rejects request with a bad token at {rbac_proxy_base}")
        print("Expected: HTTP 401 Unauthorized")

        headers = {"Authorization": "Bearer not-a-valid-token"}
        response = http_client.get(f"{rbac_proxy_base}/connection-types", headers=headers)

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code == 401, (
            f"expected HTTP 401, got {response.status_code}: {response.text}"
        )

    def test_rest_user_no_x_tenant_id_header(self, rest_base: str) -> None:
        print(f"\nTesting: rest-service rejects request with no x-tenant-id header at {rest_base}")
        print("Expected: error code 'header_not_found'")

        response = httpx.get(f"{rest_base}/connection-types")

        body = response.json()
        print(f"Response body: {body}")
        assert body.get("code") == "header_not_found", (
            f"expected code 'header_not_found', got {body.get('code')!r}"
        )
        assert body.get("message") == "Header 'x-tenant-id' not found", (
            f"expected message \"Header 'x-tenant-id' not found\", got {body.get('message')!r}"
        )

    def test_rest_user_bad_x_tenant_id_header(
        self,
        http_client: httpx.Client,
        rest_base: str,
        dch_user_token: str,
    ) -> None:
        print(f"\nTesting: rest-service rejects request with bad x-tenant-id header at {rest_base}")
        print("Expected: HTTP 200 OK")

        headers = {
            "Authorization": f"Bearer {dch_user_token}",
            "X-Tenant-Id": "not-a-valid-tenant-id",
        }
        response = http_client.get(f"{rest_base}/connection-types", headers=headers)

        print(f"HTTP status: {response.status_code}")
        print(f"Response body: {response.text}")
        assert response.status_code == 200, (
            f"expected HTTP 200, got {response.status_code}: {response.text}"
        )
