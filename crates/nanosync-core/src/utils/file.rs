//! 文件操作工具

use crate::error::Result;
use std::path::Path;
use std::io::{Read, Write};
use walkdir::WalkDir;

/// 读取文件为字符串
pub fn read_file_to_string(path: &Path) -> Result<String> {
    let content = std::fs::read_to_string(path)?;
    Ok(content)
}

/// 读取文件为字节
pub fn read_file_to_bytes(path: &Path) -> Result<Vec<u8>> {
    let content = std::fs::read(path)?;
    Ok(content)
}

/// 写入字符串到文件
pub fn write_string_to_file(path: &Path, content: &str) -> Result<()> {
    super::path::ensure_parent_directory(path)?;
    std::fs::write(path, content)?;
    Ok(())
}

/// 写入字节到文件
pub fn write_bytes_to_file(path: &Path, content: &[u8]) -> Result<()> {
    super::path::ensure_parent_directory(path)?;
    std::fs::write(path, content)?;
    Ok(())
}

/// 复制文件
pub fn copy_file(src: &Path, dst: &Path) -> Result<u64> {
    super::path::ensure_parent_directory(dst)?;
    let bytes = std::fs::copy(src, dst)?;
    Ok(bytes)
}

/// 移动文件
pub fn move_file(src: &Path, dst: &Path) -> Result<()> {
    super::path::ensure_parent_directory(dst)?;
    std::fs::rename(src, dst)?;
    Ok(())
}

/// 删除文件
pub fn delete_file(path: &Path) -> Result<()> {
    if path.exists() {
        std::fs::remove_file(path)?;
    }
    Ok(())
}

/// 删除目录（递归）
pub fn delete_directory(path: &Path) -> Result<()> {
    if path.exists() {
        std::fs::remove_dir_all(path)?;
    }
    Ok(())
}

/// 递归列出目录中所有文件
pub fn list_files_recursive(dir: &Path) -> Result<Vec<std::path::PathBuf>> {
    let mut files = Vec::new();
    
    for entry in WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_file() {
            files.push(entry.path().to_path_buf());
        }
    }
    
    Ok(files)
}

/// 列出目录中直接子项
pub fn list_directory(dir: &Path) -> Result<Vec<std::fs::DirEntry>> {
    let mut entries = Vec::new();
    
    for entry in std::fs::read_dir(dir)? {
        entries.push(entry?);
    }
    
    Ok(entries)
}

/// 检查文件是否存在
pub fn file_exists(path: &Path) -> bool {
    path.exists() && path.is_file()
}

/// 检查目录是否存在
pub fn dir_exists(path: &Path) -> bool {
    path.exists() && path.is_dir()
}

/// 获取文件大小
pub fn file_size(path: &Path) -> Result<u64> {
    let metadata = path.metadata()?;
    Ok(metadata.len())
}

/// 获取目录大小（递归计算）
pub fn directory_size(dir: &Path) -> Result<u64> {
    let mut total_size = 0;
    
    for entry in WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_file() {
            if let Ok(metadata) = entry.metadata() {
                total_size += metadata.len();
            }
        }
    }
    
    Ok(total_size)
}

/// 获取文件数量
pub fn count_files(dir: &Path) -> Result<usize> {
    let files = list_files_recursive(dir)?;
    Ok(files.len())
}

/// 格式化文件大小为人类可读格式
pub fn format_size(size: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    const TB: u64 = GB * 1024;

    if size >= TB {
        format!("{:.2} TB", size as f64 / TB as f64)
    } else if size >= GB {
        format!("{:.2} GB", size as f64 / GB as f64)
    } else if size >= MB {
        format!("{:.2} MB", size as f64 / MB as f64)
    } else if size >= KB {
        format!("{:.2} KB", size as f64 / KB as f64)
    } else {
        format!("{} B", size)
    }
}

/// 检查文件是否为文本文件
pub fn is_text_file(path: &Path) -> bool {
    if let Ok(mut file) = std::fs::File::open(path) {
        let mut buffer = [0u8; 8192];
        if let Ok(bytes_read) = file.read(&mut buffer) {
            if bytes_read == 0 {
                return true;
            }
            
            // 检查是否有空字节（通常表示二进制文件）
            if buffer[..bytes_read].contains(&0) {
                return false;
            }
            
            // 检查是否主要是可打印字符
            let printable_count = buffer[..bytes_read]
                .iter()
                .filter(|&&b| b.is_ascii_graphic() || b.is_ascii_whitespace() || b == b'\n' || b == b'\r')
                .count();
            
            let ratio = printable_count as f64 / bytes_read as f64;
            return ratio > 0.9;
        }
    }
    
    false
}

/// 获取唯一文件名（如果存在则添加编号）
pub fn unique_filename(path: &Path) -> std::path::PathBuf {
    if !path.exists() {
        return path.to_path_buf();
    }
    
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("");
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    
    let mut counter = 1;
    loop {
        let new_name = if ext.is_empty() {
            format!("{} ({})", stem, counter)
        } else {
            format!("{} ({}).{}", stem, counter, ext)
        };
        
        let new_path = parent.join(&new_name);
        if !new_path.exists() {
            return new_path;
        }
        
        counter += 1;
    }
}

/// 临时文件guard
pub struct TempFile {
    path: std::path::PathBuf,
}

impl TempFile {
    pub fn new(suffix: &str) -> Result<Self> {
        let temp_dir = std::env::temp_dir();
        let filename = format!("nanosync_{}_{}", uuid::Uuid::new_v4(), suffix);
        let path = temp_dir.join(filename);
        
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn create(&self) -> Result<std::fs::File> {
        let file = std::fs::File::create(&self.path)?;
        Ok(file)
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_size() {
        assert_eq!(format_size(500), "500 B");
        assert_eq!(format_size(1024), "1.00 KB");
        assert_eq!(format_size(1536), "1.50 KB");
        assert_eq!(format_size(1048576), "1.00 MB");
        assert_eq!(format_size(1073741824), "1.00 GB");
    }
}