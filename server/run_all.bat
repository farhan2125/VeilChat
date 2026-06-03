@echo off
echo Starting VeilChat Servers...

:: Start the main server in a new window
start "Chat Server" python server.py

:: Start the media server in the current window
echo Starting Media Server...
python media_server.py

pause