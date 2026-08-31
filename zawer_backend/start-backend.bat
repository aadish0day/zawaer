@echo off
title ZAWER Backend Server
cd /d "%~dp0"

echo ===================================================
echo             Starting ZAWER Backend
echo ===================================================
echo.

:: Check if Node.js is installed
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js is not found in your PATH.
    echo Please install Node.js from https://nodejs.org/ and try again.
    echo.
    pause
    exit /b 1
)

:: Check if .env file exists, create from .env.example if missing
if not exist ".env" (
    if exist ".env.example" (
        echo [INFO] .env not found. Creating .env from .env.example...
        copy .env.example .env >nul
    )
)

:: Check if node_modules exists, install dependencies if missing
if not exist "node_modules\" (
    echo [INFO] Dependencies not found. Running npm install...
    echo.
    call npm install
    if %errorlevel% neq 0 (
        echo.
        echo [ERROR] npm install failed. Please check your internet connection.
        echo.
        pause
        exit /b 1
    )
    echo.
)

echo Starting server on port 5000...
echo Close this window to stop the server.
echo.

:: Try running in development mode with nodemon, fallback to npm start
call npm run dev
if %errorlevel% neq 0 (
    echo.
    echo [INFO] 'npm run dev' exited. Starting with 'npm start'...
    call npm start
)

pause