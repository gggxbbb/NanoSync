@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

echo ===================================
echo NanoSync 安装器构建工具
echo ===================================
echo.

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

set ISCC_PATH=
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set ISCC_PATH=C:\Program Files\Inno Setup 6\ISCC.exe
) else (
    echo [错误] 未找到 Inno Setup 6！
    echo 请从以下地址下载安装：
    echo https://jrsoftware.org/isdl.php
    pause
    exit /b 1
)

if not exist "..\build\windows\x64\runner\Release\nano_sync.exe" (
    echo [错误] 未找到 Release 构建！
    echo.
    echo 请先运行以下命令构建 Release 版本：
    echo   flutter build windows --release
    echo.
    pause
    exit /b 1
)

if not exist "resources" mkdir resources

if not exist "resources\icon.ico" (
    echo [警告] 未找到 resources\icon.ico
    if exist "..\windows\runner\resources\app_icon.ico" (
        echo [信息] 正在复制图标文件...
        copy "..\windows\runner\resources\app_icon.ico" "resources\icon.ico" >nul
    ) else (
        echo [错误] 未找到图标源文件！
        pause
        exit /b 1
    )
)

if not exist "resources\license.txt" (
    echo [警告] 未找到 resources\license.txt
    if exist "..\LICENSE" (
        echo [信息] 正在复制许可证文件...
        copy "..\LICENSE" "resources\license.txt" >nul
    ) else (
        echo [警告] 未找到 LICENSE 文件，将创建默认 MIT 协议...
        (
            echo MIT License
            echo.
            echo Copyright (c) 2026 NanoSync Team
            echo.
            echo Permission is hereby granted, free of charge, to any person obtaining a copy
            echo of this software and associated documentation files (the "Software"), to deal
            echo in the Software without restriction, including without limitation the rights
            echo to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            echo copies of the Software, and to permit persons to whom the Software is
            echo furnished to do so, subject to the following conditions:
            echo.
            echo The above copyright notice and this permission notice shall be included in all
            echo copies or substantial portions of the Software.
            echo.
            echo THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            echo IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            echo FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            echo AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            echo LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            echo OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            echo SOFTWARE.
        ) > resources\license.txt
    )
)

if not exist "Output" mkdir Output

echo [1/2] 正在编译安装器...
echo.

"%ISCC_PATH%" setup.iss

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ===================================
    echo [成功] 安装器构建完成！
    echo ===================================
    echo.
    echo 输出文件: %SCRIPT_DIR%Output\NanoSync-Setup-1.0.0.exe
    echo.
    
    for %%F in ("Output\NanoSync-Setup-1.0.0.exe") do (
        set SIZE=%%~zF
        set /a SIZE_MB=!SIZE! / 1048576
        echo 文件大小: !SIZE_MB! MB
    )
    echo.
    
    choice /C YN /M "是否打开输出目录"
    if errorlevel 2 goto :end
    if errorlevel 1 explorer "%SCRIPT_DIR%Output"
) else (
    echo.
    echo ===================================
    echo [错误] 安装器编译失败！
    echo ===================================
    echo.
    echo 请检查 setup.iss 脚本是否有语法错误。
)

:end
pause
