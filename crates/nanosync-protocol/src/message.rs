//! IPC 消息类型定义

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// IPC 消息包装
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcMessage {
    /// 消息ID（用于请求-响应匹配）
    pub id: String,
    /// 消息类型
    pub kind: MessageKind,
    /// 消息负载
    pub payload: serde_json::Value,
    /// 时间戳
    pub timestamp: String,
}

impl IpcMessage {
    pub fn new(kind: MessageKind, payload: impl Serialize) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            kind,
            payload: serde_json::to_value(payload).unwrap_or(serde_json::Value::Null),
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }

    pub fn request(command: impl Serialize) -> Self {
        Self::new(MessageKind::Request, command)
    }

    pub fn response<T: Serialize>(request_id: &str, result: T) -> Self {
        let mut msg = Self::new(MessageKind::Response, result);
        msg.id = request_id.to_string();
        msg
    }

    pub fn error(request_id: &str, error: &str) -> Self {
        let mut msg = Self::new(MessageKind::Error, ErrorResponse {
            error: error.to_string(),
        });
        msg.id = request_id.to_string();
        msg
    }

    pub fn event(event_type: &str, data: impl Serialize) -> Self {
        Self::new(MessageKind::Event, EventPayload {
            event_type: event_type.to_string(),
            data: serde_json::to_value(data).unwrap_or(serde_json::Value::Null),
        })
    }

    pub fn parse<T: for<'de> Deserialize<'de>>(&self) -> Result<T, serde_json::Error> {
        serde_json::from_value(self.payload.clone())
    }
}

/// 消息类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MessageKind {
    Request,
    Response,
    Error,
    Event,
}

/// 错误响应
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
}

/// 事件负载
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventPayload {
    pub event_type: String,
    pub data: serde_json::Value,
}

/// 服务状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceStatus {
    pub version: String,
    pub uptime_seconds: u64,
    pub repositories_count: i32,
    pub active_syncs: i32,
    pub automation_running: bool,
}

/// 连接信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionInfo {
    pub client_id: String,
    pub connected_at: String,
    pub protocol_version: String,
}