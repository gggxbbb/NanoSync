//! 忽略规则模块
//!
//! 支持多种忽略规则语法：
//! - glob 模式 (默认)
//! - 正则表达式 (re: 或 regex: 前缀)
//! - 斜杠分隔模式 (/pattern/)

use crate::error::{Error, Result};
use regex::Regex;
use std::path::Path;

/// 忽略规则类型
#[derive(Debug, Clone)]
pub enum IgnorePattern {
    Glob(glob::Pattern),
    Regex(Regex),
}

/// 单条忽略规则
#[derive(Debug, Clone)]
pub struct IgnoreRule {
    pub pattern: IgnorePattern,
    pub original: String,
    pub negated: bool,  // 是否为否定模式 (!pattern)
}

impl IgnoreRule {
    /// 解析忽略规则字符串
    pub fn parse(pattern_str: &str) -> Result<Self> {
        let original = pattern_str.trim().to_string();
        
        if original.is_empty() || original.starts_with('#') {
            return Err(Error::IgnorePattern("忽略规则不能为空或注释".to_string()));
        }

        let (negated, pattern_str) = if original.starts_with('!') {
            (true, &original[1..])
        } else {
            (false, original.as_str())
        };

        let pattern = if let Some(rest) = pattern_str.strip_prefix("re:").or_else(|| pattern_str.strip_prefix("regex:")) {
            // 正则表达式模式
            Regex::new(rest)
                .map(IgnorePattern::Regex)
                .map_err(|e| Error::IgnorePattern(format!("无效的正则表达式: {}", e)))?
        } else if pattern_str.starts_with('/') && pattern_str.ends_with('/') && pattern_str.len() > 2 {
            // 斜杠分隔的正则表达式
            let inner = &pattern_str[1..pattern_str.len() - 1];
            Regex::new(inner)
                .map(IgnorePattern::Regex)
                .map_err(|e| Error::IgnorePattern(format!("无效的正则表达式: {}", e)))?
        } else {
            // glob 模式
            glob::Pattern::new(pattern_str)
                .map(IgnorePattern::Glob)
                .map_err(|e| Error::IgnorePattern(format!("无效的glob模式: {}", e)))?
        };

        Ok(Self {
            pattern,
            original,
            negated,
        })
    }

    /// 检查路径是否匹配此规则
    pub fn matches(&self, path: &Path) -> bool {
        let path_str = path.to_string_lossy();
        let matches = match &self.pattern {
            IgnorePattern::Glob(glob_pattern) => {
                glob_pattern.matches_path(path)
            }
            IgnorePattern::Regex(regex) => {
                regex.is_match(&path_str)
            }
        };

        if self.negated {
            !matches
        } else {
            matches
        }
    }
}

/// 忽略规则集合
#[derive(Debug, Clone)]
pub struct IgnoreRules {
    rules: Vec<IgnoreRule>,
}

impl IgnoreRules {
    pub fn new() -> Self {
        Self { rules: Vec::new() }
    }

    /// 从内容解析忽略规则
    pub fn parse(content: &str) -> Result<Self> {
        let mut rules = Vec::new();
        
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            
            match IgnoreRule::parse(line) {
                Ok(rule) => rules.push(rule),
                Err(e) => {
                    tracing::warn!("忽略无效的忽略规则 '{}': {}", line, e);
                }
            }
        }

        Ok(Self { rules })
    }

    /// 从文件加载忽略规则
    pub fn load_from_file(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        Self::parse(&content)
    }

    /// 添加规则
    pub fn add_rule(&mut self, rule: IgnoreRule) {
        self.rules.push(rule);
    }

    /// 检查路径是否应该被忽略
    pub fn is_ignored(&self, path: &Path) -> bool {
        for rule in &self.rules {
            if rule.matches(path) {
                return true;
            }
        }
        false
    }

    /// 获取所有规则
    pub fn rules(&self) -> &[IgnoreRule] {
        &self.rules
    }

    /// 是否为空
    pub fn is_empty(&self) -> bool {
        self.rules.is_empty()
    }
}

/// 默认忽略规则
pub const DEFAULT_IGNORE_PATTERNS: &[&str] = &[
    ".nanosync",
    ".git",
    ".svn",
    ".hg",
    ".DS_Store",
    "Thumbs.db",
    "*.swp",
    "*.swo",
    "*~",
    "*.tmp",
    "*.temp",
    "*.bak",
    "*.log",
];

impl Default for IgnoreRules {
    fn default() -> Self {
        let mut rules = Self::new();
        
        for pattern in DEFAULT_IGNORE_PATTERNS {
            if let Ok(rule) = IgnoreRule::parse(pattern) {
                rules.add_rule(rule);
            }
        }

        // 默认忽略 .nanosyncignore 文件本身
        if let Ok(rule) = IgnoreRule::parse(".nanosyncignore") {
            rules.add_rule(rule);
        }

        rules
    }
}

/// 忽略规则管理器
pub struct IgnoreManager {
    /// 全局默认规则
    default_rules: IgnoreRules,
    /// 仓库特定的忽略规则
    repo_rules: Option<IgnoreRules>,
    /// .nanosyncignore 文件路径
    ignore_file_path: Option<std::path::PathBuf>,
}

impl IgnoreManager {
    /// 创建新的忽略规则管理器
    pub fn new() -> Self {
        Self {
            default_rules: IgnoreRules::default(),
            repo_rules: None,
            ignore_file_path: None,
        }
    }

    /// 为仓库创建忽略规则管理器
    pub fn for_repository(repo_path: &Path) -> Result<Self> {
        let ignore_file = repo_path.join(".nanosyncignore");
        let repo_rules = if ignore_file.exists() {
            Some(IgnoreRules::load_from_file(&ignore_file)?)
        } else {
            None
        };

        Ok(Self {
            default_rules: IgnoreRules::default(),
            repo_rules,
            ignore_file_path: Some(ignore_file),
        })
    }

    /// 检查路径是否应该被忽略
    pub fn is_ignored(&self, path: &Path) -> bool {
        // 先检查默认规则
        if self.default_rules.is_ignored(path) {
            return true;
        }

        // 再检查仓库特定规则
        if let Some(repo_rules) = &self.repo_rules {
            if repo_rules.is_ignored(path) {
                return true;
            }
        }

        false
    }

    /// 重新加载忽略规则
    pub fn reload(&mut self) -> Result<()> {
        if let Some(ignore_file) = &self.ignore_file_path {
            if ignore_file.exists() {
                self.repo_rules = Some(IgnoreRules::load_from_file(ignore_file)?);
            }
        }
        Ok(())
    }

    /// 创建默认的 .nanosyncignore 文件
    pub fn create_default_ignore_file(repo_path: &Path) -> Result<()> {
        let ignore_file = repo_path.join(".nanosyncignore");
        if ignore_file.exists() {
            return Ok(());
        }

        let content = r#"# NanoSync 忽略规则文件
# 每行一个规则，支持 glob 模式

# 系统文件
.DS_Store
Thumbs.db

# 编辑器临时文件
*.swp
*.swo
*~

# 日志文件
*.log

# 构建输出
/build/
/dist/
/target/

# 依赖目录
/node_modules/
/vendor/

# 临时文件
*.tmp
*.temp
*.bak
"#;

        std::fs::write(&ignore_file, content)?;
        Ok(())
    }
}

impl Default for IgnoreManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_glob_pattern() {
        let rule = IgnoreRule::parse("*.txt").unwrap();
        assert!(!rule.negated);
        assert!(rule.matches(Path::new("test.txt")));
        assert!(rule.matches(Path::new("dir/test.txt")));
        assert!(!rule.matches(Path::new("test.doc")));
    }

    #[test]
    fn test_parse_negated_pattern() {
        let rule = IgnoreRule::parse("!important.txt").unwrap();
        assert!(rule.negated);
        // 注意：negated 标记只是标记，实际匹配逻辑需要在上层处理
    }

    #[test]
    fn test_parse_regex_pattern() {
        let rule = IgnoreRule::parse("re:^test-\\d+\\.txt$").unwrap();
        assert!(rule.matches(Path::new("test-123.txt")));
        assert!(!rule.matches(Path::new("test-abc.txt")));
    }

    #[test]
    fn test_ignore_rules() {
        let mut rules = IgnoreRules::new();
        rules.add_rule(IgnoreRule::parse("*.log").unwrap());
        rules.add_rule(IgnoreRule::parse("/build/").unwrap());

        assert!(rules.is_ignored(Path::new("error.log")));
        assert!(rules.is_ignored(Path::new("build/output")));
        assert!(!rules.is_ignored(Path::new("main.rs")));
    }

    #[test]
    fn test_default_ignore_rules() {
        let rules = IgnoreRules::default();
        assert!(rules.is_ignored(Path::new(".git")));
        assert!(rules.is_ignored(Path::new(".DS_Store")));
        assert!(rules.is_ignored(Path::new("test.swp")));
    }
}