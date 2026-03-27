//! 设备身份识别模块

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::env;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DeviceIdentityError {
    #[error("无法获取机器名")]
    CannotGetHostname,
    #[error("无法获取用户名")]
    CannotGetUsername,
}

/// 设备身份信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceIdentity {
    pub fingerprint: String,
    pub machine_name: String,
    pub username: String,
    pub os_version: String,
    pub cpu_info: Option<String>,
    pub domain: Option<String>,
}

impl DeviceIdentity {
    /// 创建当前设备的身份信息
    pub fn create() -> Result<Self, DeviceIdentityError> {
        let machine_name = hostname::get()
            .map_err(|_| DeviceIdentityError::CannotGetHostname)?
            .to_string_lossy()
            .to_string();

        let username = whoami::username();

        let os_version = Self::get_os_version();

        let cpu_info = Self::get_cpu_info();

        let domain = Self::get_domain();

        // 生成指纹
        let fingerprint = Self::generate_fingerprint(
            &machine_name,
            &username,
            &os_version,
            cpu_info.as_deref(),
            domain.as_deref(),
        );

        Ok(Self {
            fingerprint,
            machine_name: machine_name.to_string(),
            username: username.to_string(),
            os_version,
            cpu_info,
            domain,
        })
    }

    /// 从缓存或创建新的设备身份
    pub fn load_or_create(cache_path: Option<&std::path::Path>) -> Self {
        if let Some(path) = cache_path {
            if path.exists() {
                if let Ok(content) = std::fs::read_to_string(path) {
                    if let Ok(identity) = serde_json::from_str::<DeviceIdentity>(&content) {
                        return identity;
                    }
                }
            }
        }

        let identity = Self::create().unwrap_or_else(|_| Self {
            fingerprint: uuid::Uuid::new_v4().to_string(),
            machine_name: "unknown".to_string(),
            username: "unknown".to_string(),
            os_version: "unknown".to_string(),
            cpu_info: None,
            domain: None,
        });

        if let Some(path) = cache_path {
            if let Ok(content) = serde_json::to_string_pretty(&identity) {
                let _ = std::fs::write(path, content);
            }
        }

        identity
    }

    /// 生成设备指纹
    fn generate_fingerprint(
        machine_name: &str,
        username: &str,
        os_version: &str,
        cpu_info: Option<&str>,
        domain: Option<&str>,
    ) -> String {
        let mut hasher = Sha256::new();

        hasher.update(machine_name.as_bytes());
        hasher.update(username.as_bytes());
        hasher.update(os_version.as_bytes());

        if let Some(cpu) = cpu_info {
            hasher.update(cpu.as_bytes());
        }

        if let Some(domain) = domain {
            hasher.update(domain.as_bytes());
        }

        let result = hasher.finalize();
        format!("{:x}", result)
    }

    /// 获取操作系统版本
    fn get_os_version() -> String {
        #[cfg(target_os = "windows")]
        {
            if let Ok(output) = Command::new("cmd")
                .args(["/C", "ver"])
                .output()
            {
                return String::from_utf8_lossy(&output.stdout).trim().to_string();
            }
        }

        #[cfg(target_os = "linux")]
        {
            if let Ok(content) = std::fs::read_to_string("/etc/os-release") {
                for line in content.lines() {
                    if line.starts_with("PRETTY_NAME=") {
                        return line.replace("PRETTY_NAME=", "").trim_matches('"').to_string();
                    }
                }
            }
        }

        #[cfg(target_os = "macos")]
        {
            if let Ok(output) = Command::new("sw_vers").arg("-productVersion").output() {
                return format!("macOS {}", String::from_utf8_lossy(&output.stdout).trim());
            }
        }

        env::consts::OS.to_string()
    }

    /// 获取 CPU 信息
    fn get_cpu_info() -> Option<String> {
        #[cfg(target_os = "windows")]
        {
            if let Ok(output) = Command::new("wmic")
                .args(["cpu", "get", "name"])
                .output()
            {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let lines: Vec<&str> = stdout
                    .lines()
                    .filter(|l| !l.trim().is_empty())
                    .collect();
                if lines.len() > 1 {
                    return Some(lines[1].trim().to_string());
                }
            }
        }

        #[cfg(target_os = "linux")]
        {
            if let Ok(content) = std::fs::read_to_string("/proc/cpuinfo") {
                for line in content.lines() {
                    if line.starts_with("model name") {
                        return Some(line.split(':').nth(1)?.trim().to_string());
                    }
                }
            }
        }

        None
    }

    /// 获取域名
    fn get_domain() -> Option<String> {
        #[cfg(target_os = "windows")]
        {
            if let Ok(output) = Command::new("cmd")
                .args(["/C", "echo %USERDOMAIN%"])
                .output()
            {
                let domain = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !domain.is_empty() && domain != "%USERDOMAIN%" {
                    return Some(domain);
                }
            }
        }

        None
    }

    /// 匿名化的用户名
    pub fn anonymized_username(&self) -> String {
        if self.username.len() <= 2 {
            return "*".repeat(self.username.len());
        }

        let mut chars: Vec<char> = self.username.chars().collect();
        for i in 1..chars.len() - 1 {
            chars[i] = '*';
        }
        chars.into_iter().collect()
    }

    /// 显示名称
    pub fn display_name(&self) -> String {
        format!("{}@{}", self.username, self.machine_name)
    }
}

impl Default for DeviceIdentity {
    fn default() -> Self {
        Self::create().unwrap_or_else(|_| Self {
            fingerprint: uuid::Uuid::new_v4().to_string(),
            machine_name: "unknown".to_string(),
            username: "unknown".to_string(),
            os_version: "unknown".to_string(),
            cpu_info: None,
            domain: None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_identity_create() {
        let identity = DeviceIdentity::create();
        assert!(identity.is_ok());
        let identity = identity.unwrap();
        assert!(!identity.fingerprint.is_empty());
        assert!(!identity.machine_name.is_empty());
    }

    #[test]
    fn test_anonymized_username() {
        let identity = DeviceIdentity {
            fingerprint: "test".to_string(),
            machine_name: "test-machine".to_string(),
            username: "administrator".to_string(),
            os_version: "Windows 11".to_string(),
            cpu_info: None,
            domain: None,
        };

        let anon = identity.anonymized_username();
        assert_eq!(anon, "a**********r");
    }
}