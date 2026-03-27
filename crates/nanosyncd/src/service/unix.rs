//! Unix 服务管理

/// 安装服务（Unix 上需要手动配置）
pub fn install_service(name: &str) -> anyhow::Result<()> {
    println!("在 Unix 系统上，请手动配置 systemd 服务");
    println!("示例 systemd 服务文件:");
    println!();
    println!("[Unit]");
    println!("Description=NanoSync Daemon");
    println!("After=network.target");
    println!();
    println!("[Service]");
    println!("Type=simple");
    println!("ExecStart=/usr/bin/nanosyncd run");
    println!("Restart=on-failure");
    println!("RestartSec=5");
    println!();
    println!("[Install]");
    println!("WantedBy=multi-user.target");
    println!();
    println!("保存到 /etc/systemd/system/{}.service", name);
    println!("然后运行: sudo systemctl enable --now {}", name);

    Ok(())
}

/// 卸载服务
pub fn uninstall_service(name: &str) -> anyhow::Result<()> {
    println!("请运行以下命令卸载服务:");
    println!("  sudo systemctl stop {}", name);
    println!("  sudo systemctl disable {}", name);
    println!("  sudo rm /etc/systemd/system/{}.service", name);
    println!("  sudo systemctl daemon-reload");

    Ok(())
}