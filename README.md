# znake
A simple terminal snake game written in zig. It probably won't run on Windows. Works with Linux. May work on Unix-like platforms, WSL(2), MacOS, BSD, etc.

## Installation:
* install [zig](https://ziglang.org/download/). You'll want the latest Master version. May not compile in the future if I don't maintain it, but if so, you can compile it with [this](https://github.com/ziglang/zig/tree/93e11b824a37a14fc392bfc64ed8f364f4fc7d46) version of zig, which you'll have to compile from source.
* git clone this repository
* Enter the znake folder
* Run this installation command:
```bash
sudo zig build -Drelease-safe=true -p /usr
```
* Uninstall command:
```bash
sudo zig build uninstall -p /usr
```

## Controls
Move: Arrow keys  
Reset: R (after dying)
