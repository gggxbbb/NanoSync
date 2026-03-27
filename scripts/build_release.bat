@echo off
chcp 65001 >nul

echo ===================================
echo NanoSync Release 构建工具
echo ===================================
echo.

cd /d "%~dp0.."

echo [1/3] 清理旧的构建文件...
if exist "build\windows\x64\runner\Release" (
    rmdir /s /q "build\windows\x64\runner\Release"
)

echo [2/3] 正在构建 Release 版本...
flutter build windows --release

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [错误] 构建失败！
    pause
    exit /b 1
)

echo.
echo [3/3] 构建完成！
echo.
echo 输出目录: build\windows\x64\runner\Release\
echo.

dir "build\windows\x64\runner\Release" | find "文件"

echo.
echo ===================================
echo 下一步：运行 installer\build_installer.bat 构建安装器
echo ===================================

pause
