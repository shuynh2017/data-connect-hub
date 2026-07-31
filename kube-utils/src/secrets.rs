use commons::api::connections::{Secret, SecretStore};
use commons::errors::SecretStoreError;
use k8s_openapi::api::core::v1::Secret as K8sSecret;
use kube::{Api, Client};
use std::collections::HashMap;

pub struct KubeSecretStore {
    client: Client,
}

impl KubeSecretStore {
    pub fn new(client: Client) -> Self {
        Self { client }
    }

    pub async fn try_default() -> Result<Self, kube::Error> {
        let client = Client::try_default().await?;
        Ok(Self { client })
    }
}

#[async_trait::async_trait]
impl SecretStore for KubeSecretStore {
    async fn get_secret(&self, namespace: &str, name: &str) -> Result<Secret, SecretStoreError> {
        let api: Api<K8sSecret> = Api::namespaced(self.client.clone(), namespace);

        let k8s_secret = api
            .get(name)
            .await
            .map_err(|e| SecretStoreError::SecretNotFound(format!("Failed to get secret {namespace}/{name}: {e}")))?;

        let properties = k8s_secret
            .data
            .unwrap_or_default()
            .into_iter()
            .filter_map(|(key, value)| String::from_utf8(value.0).ok().map(|v| (key, v)))
            .collect::<HashMap<String, String>>();

        Ok(Secret {
            name: name.to_string(),
            namespace: namespace.to_string(),
            properties,
        })
    }
}
