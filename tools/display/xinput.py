"""Mouse and keyboard on the headless display, without xdotool (26 Nov): XTest through ctypes (libXtst.so.6 is on the
Spark, its headers and xdotool are not). Usage, DISPLAY set:
  xinput.py move X Y | click [BUTTON] | down BUTTON | up BUTTON | drag X1 Y1 X2 Y2 [STEPS] | key KEYSYM[+KEYSYM...] | type TEXT
  | wheel up|down [N] | place WINDOW_ID X Y W H (no window manager: move/resize/raise/focus a window) | focus WINDOW_ID (keyboard focus only,
  stacking unchanged: the editor throttles itself to ~3 fps when it is not the focused window)
Several commands can be chained with ';' as one argument list: xinput.py move 10 10 ';' click 1"""
import ctypes
import sys
import time

x11 = ctypes.CDLL("libX11.so.6")
xt = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
x11.XKeysymToKeycode.restype = ctypes.c_ubyte
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XFlush.argtypes = [ctypes.c_void_p]
x11.XMoveResizeWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint]
x11.XRaiseWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
for f, args in (("XTestFakeMotionEvent", [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]),
                ("XTestFakeButtonEvent", [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]),
                ("XTestFakeKeyEvent", [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong])):
    getattr(xt, f).argtypes = args

d = x11.XOpenDisplay(None)
if not d:
    sys.exit("cannot open the display (is DISPLAY set?)")

def flush(pause=0.03):
    x11.XFlush(d)
    time.sleep(pause)

def move(x, y):
    xt.XTestFakeMotionEvent(d, -1, int(x), int(y), 0); flush()

def button(b, down):
    xt.XTestFakeButtonEvent(d, int(b), 1 if down else 0, 0); flush()

def keycode(name):
    code = x11.XKeysymToKeycode(d, x11.XStringToKeysym(name.encode()))
    if not code:
        sys.exit(f"unknown key: {name}")
    return code

SHIFTED = {c: True for c in '~!@#$%^&*()_+{}|:"<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ'}
NAMES = {' ': 'space', '.': 'period', ',': 'comma', '/': 'slash', '-': 'minus', '_': 'underscore', ':': 'colon',
         '\n': 'Return', '=': 'equal', "'": 'apostrophe', '"': 'quotedbl', ';': 'semicolon', '|': 'bar', '>': 'greater',
         '<': 'less', '(': 'parenleft', ')': 'parenright', '[': 'bracketleft', ']': 'bracketright', '$': 'dollar',
         '*': 'asterisk', '&': 'ampersand', '~': 'asciitilde', '+': 'plus', '@': 'at', '#': 'numbersign', '!': 'exclam',
         '?': 'question', '%': 'percent', '^': 'asciicircum', '{': 'braceleft', '}': 'braceright', '\\': 'backslash', '`': 'grave'}

def press(names):
    codes = [keycode(n) for n in names]
    for c in codes:
        xt.XTestFakeKeyEvent(d, c, 1, 0); flush(0.01)
    for c in reversed(codes):
        xt.XTestFakeKeyEvent(d, c, 0, 0); flush(0.01)

def run(cmd):
    op, a = cmd[0], cmd[1:]
    if op == "move": move(a[0], a[1])
    elif op == "click":
        b = int(a[0]) if a else 1; button(b, True); button(b, False)
    elif op == "down": button(a[0], True)
    elif op == "up": button(a[0], False)
    elif op == "drag":
        x1, y1, x2, y2 = map(int, a[:4]); steps = int(a[4]) if len(a) > 4 else 30
        move(x1, y1); button(1, True)
        for i in range(1, steps + 1):
            move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
        button(1, False)
    elif op == "key":
        press(a[0].split("+"))
    elif op == "type":
        for ch in " ".join(a):
            name = NAMES.get(ch, ch)
            press(["Shift_L", name] if ch in SHIFTED else [name])
            time.sleep(0.02)
    elif op == "wheel":
        b = 4 if a[0] == "up" else 5
        for _ in range(int(a[1]) if len(a) > 1 else 1):
            button(b, True); button(b, False)
    elif op == "sleep": time.sleep(float(a[0]))
    elif op == "focus":
        x11.XSetInputFocus(d, int(a[0], 0), 1, 0)
        flush(0.2)
    elif op == "place":
        w = int(a[0], 0)
        x11.XMoveResizeWindow(d, w, int(a[1]), int(a[2]), int(a[3]), int(a[4]))
        x11.XRaiseWindow(d, w)
        x11.XSetInputFocus(d, w, 1, 0)   # RevertToPointerRoot
        flush(0.3)
    else: sys.exit(f"unknown command: {op}")

cmds, cur = [], []
for tok in sys.argv[1:]:
    if tok == ";":
        cmds.append(cur); cur = []
    else:
        cur.append(tok)
if cur: cmds.append(cur)
for c in cmds:
    run(c)
