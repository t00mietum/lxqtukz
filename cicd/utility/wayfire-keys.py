#!/usr/bin/env python3

#	- Purpose: Types keys into a running Wayfire through its stipc test plugin,
#	  so a test can drive an app from the keyboard on a headless compositor.
#	  stipc keeps one keyboard on the seat with Wayfire's own keymap, which
#	  tools that bring a new virtual keyboard for every run cannot promise.
#	- Needs the ipc and stipc plugins loaded, and WAYFIRE_SOCKET set to the
#	  compositor's IPC socket.
#	- Syntax: wayfire-keys.py STEP...
#	    Tab, Up, Escape, Return, space ...   one key
#	    ctrl+Tab, ctrl+shift+Tab              a chord, modifiers held around it
#	    text:500                              lower-case letters, digits, space
#	    click:X,Y                             the left button, at X,Y on screen
#	    rclick:X,Y                            the right button, at X,Y on screen
#	  Each step is followed by a short pause, so the app has taken it before
#	  the next one comes.
#	- Syntax: wayfire-keys.py --geometry
#	  Prints the focused window's x, y, width and height. Needs the ipc-rules
#	  plugin too.

#	Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)
#	Licensed under The MIT License (MIT). Full text at:
#		https://mit-license.org/
#	SPDX-License-Identifier: MIT

import json
import os
import socket
import struct
import sys
import time

KEYS = {
	"tab": "KEY_TAB",
	"up": "KEY_UP",
	"down": "KEY_DOWN",
	"left": "KEY_LEFT",
	"right": "KEY_RIGHT",
	"escape": "KEY_ESC",
	"return": "KEY_ENTER",
	"space": "KEY_SPACE",
	"backspace": "KEY_BACKSPACE",
	"ctrl": "KEY_LEFTCTRL",
	"shift": "KEY_LEFTSHIFT",
	"alt": "KEY_LEFTALT",
}
PAUSE = 0.4


def receive(sock, size):
	data = b""
	while len(data) < size:
		chunk = sock.recv(size - len(data))
		if not chunk:
			sys.exit("wayfire-keys: Wayfire closed the socket")
		data += chunk
	return data


def call(sock, method, data):
	message = json.dumps({"method": method, "data": data}).encode()
	sock.sendall(struct.pack("<I", len(message)) + message)
	(size,) = struct.unpack_from("<I", receive(sock, 4))
	reply = json.loads(receive(sock, size))
	if reply.get("result") != "ok":
		sys.exit(f"wayfire-keys: {method} {data}: {reply}")
	return reply


def key_name(text):
	name = KEYS.get(text.lower())
	if name is None and len(text) == 1 and text.isalnum():
		name = "KEY_" + text.upper()
	if name is None:
		sys.exit(f"wayfire-keys: no key named {text!r}")
	return name


def press(sock, names):
	for name in names:
		call(sock, "stipc/feed_key", {"key": name, "state": True})
	for name in reversed(names):
		call(sock, "stipc/feed_key", {"key": name, "state": False})


def click(sock, where, button="BTN_LEFT"):
	x, y = (float(n) for n in where.split(","))
	call(sock, "stipc/move_cursor", {"x": x, "y": y})
	time.sleep(PAUSE)
	call(sock, "stipc/feed_button", {"combo": button, "mode": "full"})


def main(steps):
	path = os.environ.get("WAYFIRE_SOCKET")
	if not path:
		sys.exit("wayfire-keys: WAYFIRE_SOCKET is not set")
	sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	sock.connect(path)
	if steps == ["--geometry"]:
		g = call(sock, "window-rules/get-focused-view", {})["info"]["geometry"]
		print(g["x"], g["y"], g["width"], g["height"])
		return
	for step in steps:
		if step.startswith("click:"):
			click(sock, step[6:])
		elif step.startswith("rclick:"):
			click(sock, step[7:], "BTN_RIGHT")
		elif step.startswith("text:"):
			for char in step[5:]:
				press(sock, [key_name("space" if char == " " else char)])
		else:
			press(sock, [key_name(part) for part in step.split("+")])
		time.sleep(PAUSE)


if __name__ == "__main__":
	if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
		print("Syntax: wayfire-keys.py STEP...  such as Tab, ctrl+shift+Tab, text:500")
		sys.exit(0)
	main(sys.argv[1:])
