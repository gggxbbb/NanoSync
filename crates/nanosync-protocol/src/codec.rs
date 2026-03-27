//! IPC 编解码器

use crate::{IpcMessage, MessageKind};
use std::io::{self, Read, Write};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CodecError {
    #[error("IO错误: {0}")]
    Io(#[from] io::Error),
    
    #[error("序列化错误: {0}")]
    Serialize(#[from] serde_json::Error),
    
    #[error("无效的消息长度")]
    InvalidLength,
    
    #[error("消息过大: {0} 字节")]
    MessageTooLarge(usize),
}

pub type CodecResult<T> = Result<T, CodecError>;

/// 最大消息大小 (10MB)
pub const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024;

/// 消息编解码器
pub struct MessageCodec;

impl MessageCodec {
    /// 编码消息
    pub fn encode(message: &IpcMessage) -> CodecResult<Vec<u8>> {
        let json = serde_json::to_vec(message)?;
        let len = json.len() as u32;
        
        if json.len() > MAX_MESSAGE_SIZE {
            return Err(CodecError::MessageTooLarge(json.len()));
        }
        
        let mut buffer = Vec::with_capacity(4 + json.len());
        buffer.extend_from_slice(&len.to_be_bytes());
        buffer.extend_from_slice(&json);
        
        Ok(buffer)
    }

    /// 解码消息
    pub fn decode(data: &[u8]) -> CodecResult<IpcMessage> {
        if data.len() < 4 {
            return Err(CodecError::InvalidLength);
        }

        let len = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
        if len > MAX_MESSAGE_SIZE {
            return Err(CodecError::MessageTooLarge(len));
        }

        if data.len() < 4 + len {
            return Err(CodecError::InvalidLength);
        }

        let message: IpcMessage = serde_json::from_slice(&data[4..4 + len])?;
        Ok(message)
    }

    /// 从流读取消息
    pub fn read_from<R: Read>(reader: &mut R) -> CodecResult<IpcMessage> {
        let mut len_buf = [0u8; 4];
        reader.read_exact(&mut len_buf)?;
        
        let len = u32::from_be_bytes(len_buf) as usize;
        if len > MAX_MESSAGE_SIZE {
            return Err(CodecError::MessageTooLarge(len));
        }

        let mut msg_buf = vec![0u8; len];
        reader.read_exact(&mut msg_buf)?;

        let message: IpcMessage = serde_json::from_slice(&msg_buf)?;
        Ok(message)
    }

    /// 写入消息到流
    pub fn write_to<W: Write>(writer: &mut W, message: &IpcMessage) -> CodecResult<()> {
        let encoded = Self::encode(message)?;
        writer.write_all(&encoded)?;
        writer.flush()?;
        Ok(())
    }
}

/// 分帧读取器
pub struct FramedReader<R> {
    reader: R,
    buffer: Vec<u8>,
}

impl<R: Read> FramedReader<R> {
    pub fn new(reader: R) -> Self {
        Self {
            reader,
            buffer: Vec::new(),
        }
    }

    /// 读取下一条消息
    pub fn read_message(&mut self) -> CodecResult<Option<IpcMessage>> {
        // 尝试读取长度前缀
        if self.buffer.len() < 4 {
            let mut temp = [0u8; 4];
            let needed = 4 - self.buffer.len();
            let mut read_buf = vec![0u8; needed];
            
            match self.reader.read(&mut read_buf) {
                Ok(0) => return Ok(None), // EOF
                Ok(n) => {
                    self.buffer.extend_from_slice(&read_buf[..n]);
                    if self.buffer.len() < 4 {
                        return Ok(None);
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(None),
                Err(e) => return Err(CodecError::Io(e)),
            }
        }

        // 解析长度
        let len = u32::from_be_bytes([
            self.buffer[0],
            self.buffer[1],
            self.buffer[2],
            self.buffer[3],
        ]) as usize;

        if len > MAX_MESSAGE_SIZE {
            return Err(CodecError::MessageTooLarge(len));
        }

        // 读取完整消息
        while self.buffer.len() < 4 + len {
            let remaining = 4 + len - self.buffer.len();
            let mut read_buf = vec![0u8; remaining];
            
            match self.reader.read(&mut read_buf) {
                Ok(0) => return Ok(None), // EOF
                Ok(n) => {
                    self.buffer.extend_from_slice(&read_buf[..n]);
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(None),
                Err(e) => return Err(CodecError::Io(e)),
            }
        }

        // 解码消息
        let message: IpcMessage = serde_json::from_slice(&self.buffer[4..4 + len])?;
        
        // 清除已处理的数据
        self.buffer.drain(..4 + len);
        
        Ok(Some(message))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::PingCommand;

    #[test]
    fn test_encode_decode() {
        let msg = IpcMessage::request(PingCommand {
            message: Some("test".to_string()),
        });

        let encoded = MessageCodec::encode(&msg).unwrap();
        let decoded = MessageCodec::decode(&encoded).unwrap();

        assert_eq!(msg.id, decoded.id);
        assert_eq!(msg.kind, decoded.kind);
    }

    #[test]
    fn test_message_too_large() {
        let large_data = vec![0u8; MAX_MESSAGE_SIZE + 1];
        let msg = IpcMessage::new(MessageKind::Request, large_data.clone());
        
        let result = MessageCodec::encode(&msg);
        assert!(matches!(result, Err(CodecError::MessageTooLarge(_))));
    }
}