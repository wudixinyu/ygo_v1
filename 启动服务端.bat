@echo off
chcp 936 >nul
title 游戏王服务端 · 端口 9000

set "GODOT=K:\Users\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=K:\豆包\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo [错误] 未找到 Godot 可执行文件，请用记事本打开本脚本修改 GODOT 路径。
    pause
    exit /b 1
)

set "SERVER=%~dp0游戏王主服务"
if not exist "%SERVER%" set "SERVER=%~dp0游戏王服务端"

echo 正在启动游戏王服务端（管理界面 + 监听端口 9000）...
"%GODOT%" --path "%SERVER%"
