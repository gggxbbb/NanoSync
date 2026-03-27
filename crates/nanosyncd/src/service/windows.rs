//! Windows 服务管理

use std::ffi::OsString;
use std::time::Duration;
use windows_service::service::{
    ServiceAccess, ServiceErrorControl, ServiceInfo, ServiceStartType,
    ServiceState, ServiceType,
};
use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};

const SERVICE_NAME: &str = "nanosyncd";
const SERVICE_DISPLAY_NAME: &str = "NanoSync Daemon";
const SERVICE_DESCRIPTION: &str = "NanoSync 后台同步服务";

/// 安装 Windows 服务
pub fn install_service(name: &str) -> anyhow::Result<()> {
    let manager = ServiceManager::local_computer(
        None::<&str>,
        ServiceManagerAccess::CONNECT | ServiceManagerAccess::CREATE_SERVICE,
    )?;

    let executable_path = std::env::current_exe()?;
    
    let service_info = ServiceInfo {
        name: OsString::from(name),
        display_name: OsString::from(SERVICE_DISPLAY_NAME),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::AutoStart,
        error_control: ServiceErrorControl::Normal,
        executable_path,
        launch_arguments: vec![OsString::from("run")],
        dependencies: vec![],
        account_name: None,
        account_password: None,
    };

    let _service = manager.create_service(&service_info, ServiceAccess::QUERY_STATUS)?;
    
    println!("服务 '{}' 安装成功", name);
    println!("使用 'net start {}' 启动服务", name);
    println!("或使用 'sc start {}' 启动服务", name);

    Ok(())
}

/// 卸载 Windows 服务
pub fn uninstall_service(name: &str) -> anyhow::Result<()> {
    let manager = ServiceManager::local_computer(
        None::<&str>,
        ServiceManagerAccess::CONNECT,
    )?;

    let service = manager.open_service(
        name,
        ServiceAccess::QUERY_STATUS | ServiceAccess::STOP | ServiceAccess::DELETE,
    )?;

    // 先停止服务
    let status = service.query_status()?;
    if status.current_state != ServiceState::Stopped {
        println!("正在停止服务 '{}'...", name);
        service.stop()?;
        
        // 等待服务停止
        for _ in 0..30 {
            let status = service.query_status()?;
            if status.current_state == ServiceState::Stopped {
                break;
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    }

    // 删除服务
    service.delete()?;
    
    println!("服务 '{}' 已卸载", name);

    Ok(())
}