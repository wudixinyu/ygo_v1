@echo off
chcp 936 >nul
title 游戏王客户端

set "GODOT=K:\Users\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=K:\豆包\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo [错误] 未找到 Godot 可执行文件，请用记事本打开本脚本修改 GODOT 路径。
    pause
    exit /b 1
)

echo 正在启动客户端（默认连接 127.0.0.1:9000，可在登录页修改）...
echo 需要多开时：再次双击本脚本即可启动第二个客户端。
"%GODOT%" --path "%~dp0游戏王客户端"
