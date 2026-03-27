//! IPC 客户端

use nanosync_protocol::*;
use std::io::{Read, Write};

/// IPC 客户端
pub struct IpcClient {
    ipc_address: String,
}

impl IpcClient {
    pub fn new(ipc_address: &str) -> Self {
        Self {
            ipc_address: ipc_address.to_string(),
        }
    }

    /// 发送命令并获取响应
    pub async fn send_command(&self, command: command::Command) -> anyhow::Result<IpcMessage> {
        let request = IpcMessage::request(command);
        
        #[cfg(windows)]
        {
            self.send_command_windows(&request).await
        }
        
        #[cfg(not(windows))]
        {
            self.send_command_unix(&request).await
        }
    }

    #[cfg(windows)]
    async fn send_command_windows(&self, request: &IpcMessage) -> anyhow::Result<IpcMessage> {
        use std::os::windows::fs::OpenOptionsExt;
        use std::fs::OpenOptions;
        
        // Windows 命名管道
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(winapi::um::winbase::PIPE_ACCESS_DUPLEX)
            .open(&self.ipc_address)?;
        
        // 编码请求
        let encoded = codec::MessageCodec::encode(request)?;
        file.write_all(&encoded)?;
        
        // 读取响应
        let mut response_buf = vec![0u8; 65536];
        let n = file.read(&mut response_buf)?;
        
        // 解码响应
        let response = codec::MessageCodec::decode(&response_buf[..n])?;
        Ok(response)
    }

    #[cfg(not(windows))]
    async fn send_command_unix(&self, request: &IpcMessage) -> anyhow::Result<IpcMessage> {
        use std::os::unix::net::UnixStream;
        
        // 连接到 Unix socket
        let mut stream = UnixStream::connect(&self.ipc_address)?;
        
        // 编码请求
        let encoded = codec::MessageCodec::encode(request)?;
        stream.write_all(&encoded)?;
        
        // 读取响应
        let mut response_buf = vec![0u8; 65536];
        let n = stream.read(&mut response_buf)?;
        
        // 解码响应
        let response = codec::MessageCodec::decode(&response_buf[..n])?;
        Ok(response)
    }

    /// 检查服务是否可用
    pub async fn ping(&self) -> anyhow::Result<bool> {
        let response = self.send_command(command::Command::Ping(command::PingCommand {
            message: Some("ping".to_string()),
        })).await?;
        
        Ok(response.kind == MessageKind::Response)
    }

    /// 获取服务状态
    pub async fn get_status(&self) -> anyhow::Result<Option<ServiceStatus>> {
        let response = self.send_command(command::Command::GetStatus).await?;
        
        if response.kind == MessageKind::Response {
            Ok(response.parse::<ServiceStatus>().ok())
        } else {
            Ok(None)
        }
    }
}