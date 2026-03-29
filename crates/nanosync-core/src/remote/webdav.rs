//! WebDAV 协议实现

use crate::error::{Error, Result};
use crate::models::*;
use regex::Regex;
use reqwest::{Client, Method, StatusCode};
use std::path::Path;
use std::time::Instant;
use tokio::time::Duration;

/// WebDAV 客户端
pub struct WebDavClient {
    base_url: String,
    username: Option<String>,
    password: Option<String>,
}

impl WebDavClient {
    pub fn new(config: &WebDavConfig) -> Self {
        let mut base_url = if config.use_https {
            format!("https://{}", config.host)
        } else {
            format!("http://{}", config.host)
        };

        if let Some(port) = config.port {
            base_url = format!("{}:{}", base_url, port);
        }

        Self {
            base_url,
            username: config.username.clone(),
            password: config.password.clone(),
        }
    }

    /// 获取完整 URL
    pub fn full_url(&self, path: &str) -> String {
        let path = path.trim_start_matches('/');
        format!("{}/{}", self.base_url, path)
    }

    fn build_client() -> Result<Client> {
        Client::builder()
            .timeout(Duration::from_secs(8))
            .build()
            .map_err(|e| Error::WebDav(format!("创建 HTTP 客户端失败: {}", e)))
    }

    fn with_auth(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        if let Some(username) = self.username.as_deref() {
            builder.basic_auth(username, self.password.clone())
        } else {
            builder
        }
    }

    fn parse_remote_file_info(remote_path: &str, resp: &reqwest::Response) -> RemoteFileInfo {
        let name = remote_path
            .trim_end_matches('/')
            .rsplit('/')
            .next()
            .unwrap_or("")
            .to_string();

        let size = resp
            .headers()
            .get(reqwest::header::CONTENT_LENGTH)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(0);

        let content_type = resp
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());

        let modified_time = resp
            .headers()
            .get(reqwest::header::LAST_MODIFIED)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| chrono::DateTime::parse_from_rfc2822(s).ok())
            .map(|dt| dt.with_timezone(&chrono::Utc));

        RemoteFileInfo {
            name,
            path: remote_path.to_string(),
            is_directory: false,
            size,
            modified_time,
            content_type,
        }
    }

    fn parse_propfind_entries(xml: &str) -> Vec<RemoteFileInfo> {
        let response_re = Regex::new(r"(?s)<[^:>]*:?response[^>]*>(.*?)</[^:>]*:?response>").ok();
        let href_re = Regex::new(r"(?s)<[^:>]*:?href[^>]*>(.*?)</[^:>]*:?href>").ok();
        let len_re = Regex::new(
            r"(?s)<[^:>]*:?getcontentlength[^>]*>(\d+)</[^:>]*:?getcontentlength>",
        )
        .ok();
        let type_re = Regex::new(
            r"(?s)<[^:>]*:?getcontenttype[^>]*>(.*?)</[^:>]*:?getcontenttype>",
        )
        .ok();
        let modified_re = Regex::new(
            r"(?s)<[^:>]*:?getlastmodified[^>]*>(.*?)</[^:>]*:?getlastmodified>",
        )
        .ok();
        let collection_re = Regex::new(r"(?s)<[^:>]*:?collection\s*/>").ok();

        let Some(response_re) = response_re else {
            return Vec::new();
        };

        let mut result = Vec::new();
        for cap in response_re.captures_iter(xml) {
            let block = cap.get(1).map(|m| m.as_str()).unwrap_or_default();
            let raw_href = href_re
                .as_ref()
                .and_then(|re| re.captures(block))
                .and_then(|c| c.get(1))
                .map(|m| m.as_str().trim().to_string())
                .unwrap_or_default();

            let decoded_href = raw_href
                .replace("&amp;", "&")
                .replace("%20", " ")
                .replace("%5C", "\\")
                .replace("%2F", "/");

            let path = decoded_href.trim_end_matches('/').to_string();
            let name = path
                .rsplit('/')
                .next()
                .unwrap_or("")
                .to_string();

            if name.is_empty() {
                continue;
            }

            let size = len_re
                .as_ref()
                .and_then(|re| re.captures(block))
                .and_then(|c| c.get(1))
                .and_then(|m| m.as_str().parse::<u64>().ok())
                .unwrap_or(0);

            let content_type = type_re
                .as_ref()
                .and_then(|re| re.captures(block))
                .and_then(|c| c.get(1))
                .map(|m| m.as_str().trim().to_string());

            let modified_time = modified_re
                .as_ref()
                .and_then(|re| re.captures(block))
                .and_then(|c| c.get(1))
                .and_then(|m| chrono::DateTime::parse_from_rfc2822(m.as_str().trim()).ok())
                .map(|dt| dt.with_timezone(&chrono::Utc));

            let is_directory = collection_re
                .as_ref()
                .map(|re| re.is_match(block))
                .unwrap_or(false)
                || raw_href.ends_with('/');

            result.push(RemoteFileInfo {
                name,
                path,
                is_directory,
                size,
                modified_time,
                content_type,
            });
        }

        result
    }

    /// 测试连接
    pub async fn test_connection(&self, path: &str) -> Result<ConnectionTestResult> {
        let client = Self::build_client()?;
        let test_url = if path.trim().is_empty() {
            self.base_url.clone()
        } else {
            self.full_url(path)
        };

        let mut request = client.request(Method::OPTIONS, &test_url);
        if let Some(username) = self.username.as_deref() {
            request = request.basic_auth(username, self.password.clone());
        }

        let start = Instant::now();
        let response = match request.send().await {
            Ok(resp) => resp,
            Err(e) => {
                return Ok(ConnectionTestResult {
                    success: false,
                    message: format!("WebDAV 连接失败: {}", e),
                    details: Some(ConnectionTestDetails {
                        can_read: false,
                        can_write: false,
                        can_list: false,
                        latency_ms: None,
                        share_list: None,
                    }),
                })
            }
        };

        let latency_ms = start.elapsed().as_millis() as u64;
        let status = response.status();

        if status == StatusCode::UNAUTHORIZED || status == StatusCode::FORBIDDEN {
            return Ok(ConnectionTestResult {
                success: false,
                message: format!("WebDAV 认证失败 (HTTP {})", status.as_u16()),
                details: Some(ConnectionTestDetails {
                    can_read: false,
                    can_write: false,
                    can_list: false,
                    latency_ms: Some(latency_ms),
                    share_list: None,
                }),
            });
        }

        let ok = status.is_success();
        Ok(ConnectionTestResult {
            success: ok,
            message: if ok {
                format!("WebDAV 连接成功 (HTTP {})", status.as_u16())
            } else {
                format!("WebDAV 响应异常 (HTTP {})", status.as_u16())
            },
            details: Some(ConnectionTestDetails {
                can_read: ok,
                can_write: false,
                can_list: ok,
                latency_ms: Some(latency_ms),
                share_list: None,
            }),
        })
    }

    /// 下载文件
    pub async fn download_file(&self, remote_path: &str, local_path: &Path) -> Result<()> {
        let client = Self::build_client()?;
        let url = self.full_url(remote_path);

        let response = self
            .with_auth(client.get(&url))
            .send()
            .await
            .map_err(|e| Error::WebDav(format!("下载请求失败: {}", e)))?;

        if !response.status().is_success() {
            return Err(Error::WebDav(format!(
                "下载失败 (HTTP {}): {}",
                response.status().as_u16(),
                url
            )));
        }

        let bytes = response
            .bytes()
            .await
            .map_err(|e| Error::WebDav(format!("读取下载内容失败: {}", e)))?;

        if let Some(parent) = local_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(local_path, &bytes)?;
        Ok(())
    }

    /// 上传文件
    pub async fn upload_file(&self, local_path: &Path, remote_path: &str) -> Result<()> {
        if !local_path.exists() {
            return Err(Error::WebDav(format!(
                "本地文件不存在: {}",
                local_path.display()
            )));
        }

        let content = std::fs::read(local_path)?;
        let client = Self::build_client()?;
        let url = self.full_url(remote_path);

        let response = self
            .with_auth(client.put(&url).body(content))
            .send()
            .await
            .map_err(|e| Error::WebDav(format!("上传请求失败: {}", e)))?;

        if !(response.status().is_success()
            || response.status() == StatusCode::CREATED
            || response.status() == StatusCode::NO_CONTENT)
        {
            return Err(Error::WebDav(format!(
                "上传失败 (HTTP {}): {}",
                response.status().as_u16(),
                url
            )));
        }

        Ok(())
    }

    /// 确保目录存在
    pub async fn ensure_directory(&self, path: &str) -> Result<()> {
        if path.trim().is_empty() || path == "/" {
            return Ok(());
        }

        let client = Self::build_client()?;
        let url = self.full_url(path);

        let response = self
            .with_auth(client.request(Method::from_bytes(b"MKCOL").unwrap_or(Method::OPTIONS), &url))
            .send()
            .await
            .map_err(|e| Error::WebDav(format!("创建目录请求失败: {}", e)))?;

        if response.status().is_success() || response.status() == StatusCode::METHOD_NOT_ALLOWED {
            // 405 通常表示目录已存在
            return Ok(());
        }

        Err(Error::WebDav(format!(
            "创建目录失败 (HTTP {}): {}",
            response.status().as_u16(),
            url
        )))
    }

    /// 删除文件
    pub async fn delete_file(&self, remote_path: &str) -> Result<()> {
        let client = Self::build_client()?;
        let url = self.full_url(remote_path);

        let response = self
            .with_auth(client.delete(&url))
            .send()
            .await
            .map_err(|e| Error::WebDav(format!("删除请求失败: {}", e)))?;

        if response.status().is_success() || response.status() == StatusCode::NOT_FOUND {
            return Ok(());
        }

        Err(Error::WebDav(format!(
            "删除失败 (HTTP {}): {}",
            response.status().as_u16(),
            url
        )))
    }

    /// 列出目录
    pub async fn list_directory(&self, path: &str) -> Result<Vec<RemoteFileInfo>> {
        let client = Self::build_client()?;
        let url = self.full_url(path);

        let response = self
            .with_auth(
                client
                    .request(Method::from_bytes(b"PROPFIND").unwrap_or(Method::OPTIONS), &url)
                    .header("Depth", "1"),
            )
            .send()
            .await
            .map_err(|e| Error::WebDav(format!("PROPFIND 请求失败: {}", e)))?;

        if !(response.status().is_success() || response.status().as_u16() == 207) {
            return Err(Error::WebDav(format!(
                "列出目录失败 (HTTP {}): {}",
                response.status().as_u16(),
                url
            )));
        }

        let body = response
            .text()
            .await
            .map_err(|e| Error::WebDav(format!("读取 PROPFIND 响应失败: {}", e)))?;

        Ok(Self::parse_propfind_entries(&body))
    }

    /// 检查文件是否存在
    pub async fn file_exists(&self, remote_path: &str) -> Result<bool> {
        let client = Self::build_client()?;
        let url = self.full_url(remote_path);

        let response = self
            .with_auth(client.head(&url))
            .send()
            .await
            .map_err(|e| Error::WebDav(format!("HEAD 请求失败: {}", e)))?;

        if response.status() == StatusCode::NOT_FOUND {
            return Ok(false);
        }

        Ok(response.status().is_success())
    }

    /// 获取文件信息
    pub async fn get_file_info(&self, remote_path: &str) -> Result<Option<RemoteFileInfo>> {
        let client = Self::build_client()?;
        let url = self.full_url(remote_path);

        let response = self
            .with_auth(client.head(&url))
            .send()
            .await
            .map_err(|e| Error::WebDav(format!("获取文件信息失败: {}", e)))?;

        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }

        if !response.status().is_success() {
            return Err(Error::WebDav(format!(
                "获取文件信息失败 (HTTP {}): {}",
                response.status().as_u16(),
                url
            )));
        }

        Ok(Some(Self::parse_remote_file_info(remote_path, &response)))
    }
}

/// 远程文件信息
#[derive(Debug, Clone)]
pub struct RemoteFileInfo {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size: u64,
    pub modified_time: Option<chrono::DateTime<chrono::Utc>>,
    pub content_type: Option<String>,
}