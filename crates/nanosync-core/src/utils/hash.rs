//! 哈希计算工具

use blake3::Hasher;
use sha2::{Digest, Sha256};
use std::path::Path;

/// 计算文件内容的 BLAKE3 哈希
pub fn hash_file_blake3(path: &Path) -> std::io::Result<String> {
    use std::fs::File;
    use std::io::{BufReader, Read};

    let file = File::open(path)?;
    let mut reader = BufReader::new(file);
    
    let mut hasher = Hasher::new();
    let mut buffer = [0u8; 8192];
    
    loop {
        let bytes_read = reader.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    
    Ok(hasher.finalize().to_hex().to_string())
}

/// 计算数据的 BLAKE3 哈希
pub fn hash_bytes_blake3(data: &[u8]) -> String {
    let mut hasher = Hasher::new();
    hasher.update(data);
    hasher.finalize().to_hex().to_string()
}

/// 计算文件内容的 SHA256 哈希
pub fn hash_file_sha256(path: &Path) -> std::io::Result<String> {
    use std::fs::File;
    use std::io::{BufReader, Read};

    let file = File::open(path)?;
    let mut reader = BufReader::new(file);
    
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 8192];
    
    loop {
        let bytes_read = reader.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    
    Ok(format!("{:x}", hasher.finalize()))
}

/// 计算数据的 SHA256 哈希
pub fn hash_bytes_sha256(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    format!("{:x}", hasher.finalize())
}

/// 生成对象ID（使用BLAKE3）
pub fn generate_object_id(data: &[u8]) -> String {
    hash_bytes_blake3(data)
}

/// 生成短哈希（前12字符）
pub fn short_hash(hash: &str) -> &str {
    if hash.len() >= 12 {
        &hash[..12]
    } else {
        hash
    }
}

/// 生成UUID
pub fn generate_uuid() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// 生成带有前缀的对象ID
pub fn generate_prefixed_id(prefix: &str) -> String {
    format!("{}_{}", prefix, generate_uuid())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_bytes() {
        let data = b"hello world";
        let hash = hash_bytes_blake3(data);
        assert!(!hash.is_empty());
        assert_eq!(hash.len(), 64);
    }

    #[test]
    fn test_short_hash() {
        let hash = "abcdef1234567890";
        assert_eq!(short_hash(hash), "abcdef123456");
    }

    #[test]
    fn test_generate_uuid() {
        let uuid = generate_uuid();
        assert!(uuid.contains('-'));
        assert_eq!(uuid.len(), 36);
    }
}