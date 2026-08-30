@echo off
title ZAWER Backend Server
cd /d "%~dp0"
echo Starting ZAWER backend on port 5000...
echo Close this window to stop the server.
echo.
call node_modules\.bin\nodemon.cmd server.js
pause