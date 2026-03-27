//! 路径操作工具

use std::path::{Path, PathBuf};

/// 规范化路径
pub fn normalize_path(path: &Path) -> PathBuf {
    let mut components = path.components().peekable();
    let mut ret = PathBuf::new();

    while let Some(c) = components.next() {
        match c {
            std::path::Component::Prefix(_) => {
                ret.push(c);
            }
            std::path::Component::RootDir => {
                ret.push(c);
            }
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                if !ret.pop() {
                    ret.push("..");
                }
            }
            std::path::Component::Normal(_) => {
                ret.push(c);
            }
        }
    }

    ret
}

/// 规范化路径字符串 (使用 / 作为分隔符)
pub fn normalize_path_string(path: &str) -> String {
    path.replace('\\', "/")
        .trim_start_matches('.')
        .trim_start_matches('/')
        .trim_end_matches('/')
        .to_string()
}

/// 相对路径基准路径
pub trait RelativePathExt {
    fn relative_to(&self, base: &Path) -> Option<PathBuf>;
}

impl RelativePathExt for Path {
    fn relative_to(&self, base: &Path) -> Option<PathBuf> {
        self.strip_prefix(base).ok().map(|p| p.to_path_buf())
    }
}

/// 计算相对路径
pub fn relative_path(path: &Path, base: &Path) -> Option<PathBuf> {
    path.strip_prefix(base).ok().map(|p| p.to_path_buf())
}

/// 确保目录存在
pub fn ensure_directory(path: &Path) -> std::io::Result<()> {
    if !path.exists() {
        std::fs::create_dir_all(path)?;
    }
    Ok(())
}

/// 确保父目录存在
pub fn ensure_parent_directory(file_path: &Path) -> std::io::Result<()> {
    if let Some(parent) = file_path.parent() {
        ensure_directory(parent)?;
    }
    Ok(())
}

/// 安全拼接路径
pub fn safe_join(base: &Path, relative: &str) -> PathBuf {
    let relative = relative.trim_start_matches('/');
    base.join(relative)
}

/// 检查路径是否在指定范围内（防止目录遍历）
pub fn is_path_inside(base: &Path, path: &Path) -> bool {
    let canonical_base = match base.canonicalize() {
        Ok(p) => p,
        Err(_) => return false,
    };

    let canonical_path = match path.canonicalize() {
        Ok(p) => p,
        Err(_) => match path.to_str() {
            Some(_) => {
                // 路径可能不存在，尝试与 base 拼接后检查
                if path.is_absolute() {
                    return false;
                }
                let joined = base.join(path);
                match joined.canonicalize() {
                    Ok(p) => p,
                    Err(_) => return false,
                }
            }
            None => return false,
        },
    };

    canonical_path.starts_with(canonical_base)
}

/// 获取文件名（不含扩展名）
pub fn file_stem(path: &Path) -> Option<&str> {
    path.file_stem().and_then(|s| s.to_str())
}

/// 获取文件扩展名
pub fn file_extension(path: &Path) -> Option<&str> {
    path.extension().and_then(|s| s.to_str())
}

/// 获取 .nanosync 目录路径
pub fn nanosync_dir(repo_path: &Path) -> PathBuf {
    repo_path.join(".nanosync")
}

/// 获取 objects 目录路径
pub fn objects_dir(repo_path: &Path) -> PathBuf {
    nanosync_dir(repo_path).join("objects")
}

/// 获取 staging 目录路径
pub fn staging_dir(repo_path: &Path) -> PathBuf {
    nanosync_dir(repo_path).join("staging")
}

/// 获取仓库数据库路径
pub fn repository_db_path(repo_path: &Path) -> PathBuf {
    nanosync_dir(repo_path).join("data.db")
}

/// 获取仓库配置文件路径
pub fn repository_config_path(repo_path: &Path) -> PathBuf {
    nanosync_dir(repo_path).join("config.json")
}

/// 获取仓库状态文件路径
pub fn repository_state_path(repo_path: &Path) -> PathBuf {
    nanosync_dir(repo_path).join("repository_state.json")
}

/// 获取自动化规则目录
pub fn automation_dir(repo_path: &Path) -> PathBuf {
    nanosync_dir(repo_path).join("automation")
}

/// 获取日志目录
pub fn logs_dir(repo_path: &Path) -> PathBuf {
    nanosync_dir(repo_path).join("logs")
}

/// 确保仓库目录结构存在
pub fn ensure_repository_structure(repo_path: &Path) -> std::io::Result<()> {
    ensure_directory(&nanosync_dir(repo_path))?;
    ensure_directory(&objects_dir(repo_path))?;
    ensure_directory(&staging_dir(repo_path))?;
    ensure_directory(&automation_dir(repo_path))?;
    ensure_directory(&logs_dir(repo_path))?;
    Ok(())
}

/// 检查是否是仓库根目录
pub fn is_repository_root(path: &Path) -> bool {
    nanosync_dir(path).exists()
}

/// 查找仓库根目录（从当前目录向上查找）
pub fn find_repository_root(start_path: &Path) -> Option<PathBuf> {
    let mut current = start_path;
    loop {
        if is_repository_root(current) {
            return Some(current.to_path_buf());
        }
        current = current.parent()?;
    }
}

/// 获取对象的物理存储路径
/// objects 目录下按照哈希前两字符分组，如 .nanosync/objects/ab/cdefxxx
pub fn object_path(repo_path: &Path, object_id: &str) -> PathBuf {
    if object_id.len() >= 2 {
        objects_dir(repo_path)
            .join(&object_id[..2])
            .join(&object_id[2..])
    } else {
        objects_dir(repo_path).join(object_id)
    }
}

/// 确保对象的存储目录存在
pub fn ensure_object_parent_dir(repo_path: &Path, object_id: &str) -> std::io::Result<()> {
    if object_id.len() >= 2 {
        let subdir = objects_dir(repo_path).join(&object_id[..2]);
        ensure_directory(&subdir)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_path_string() {
        assert_eq!(normalize_path_string("\\test\\path"), "test/path");
        assert_eq!(normalize_path_string("./test/path/"), "test/path");
        assert_eq!(normalize_path_string("/test/path/"), "test/path");
    }

    #[test]
    fn test_safe_join() {
        let base = Path::new("/data");
        assert_eq!(safe_join(base, "subdir/file.txt"), base.join("subdir/file.txt"));
        assert_eq!(safe_join(base, "/subdir/file.txt"), base.join("subdir/file.txt"));
    }

    #[test]
  fn test_nanosync_dir() {
        let repo = Path::new("/data/repo");
        assert_eq!(nanosync_dir(repo), repo.join(".nanosync"));
    }

    #[test]
    fn test_object_path() {
        let repo = Path::new("/data/repo");
        let obj_id = "abcdef123456";
        let expected = repo.join(".nanosync/objects/ab/cdef123456");
        assert_eq!(object_path(repo, obj_id), expected);
    }
}