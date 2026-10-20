@echo off
chcp 936 >nul
title 游戏王测试环境 · 一键启动

set "GODOT=K:\Users\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=K:\豆包\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo [错误] 未找到 Godot 可执行文件，请用记事本打开本脚本修改 GODOT 路径。
    pause
    exit /b 1
)

set "SERVER=%~dp0游戏王主服务"
if not exist "%SERVER%" set "SERVER=%~dp0游戏王服务端"

echo ============================================
echo   游戏王联机对战 · 测试环境一键启动
echo ============================================
echo.

echo [1/2] 启动服务端（管理界面 + 玩家端口 9000）...
start "游戏王服务端" "%GODOT%" --path "%SERVER%"
timeout /t 3 /nobreak >nul

echo [2/2] 启动两个客户端（都连接 127.0.0.1:9000）...
start "游戏王客户端1" "%GODOT%" --path "%~dp0游戏王客户端"
start "游戏王客户端2" "%GODOT%" --path "%~dp0游戏王客户端"

echo.
echo 全部启动完成。接下来可以：
echo   1. 在服务端界面看到玩家登录与房间创建
echo   2. 客户端里一个创建房间、另一个加入，双方「准备」后开始决斗
echo   3. 在服务端房间总览点「进入观看」，实时观战房间画面
echo.
echo 提示：真人对战——两个客户端分别操作：第一个建房、第二个点「加入」，双方准备后轮流出牌。
echo.
pause
