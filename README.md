# Video tools

A Bash script that wraps ffmpeg for editing videos.

* Crop to start and end times
* Crop sides of image
* Resize (maintain aspect ratio, pad with black bars)
* Deinterlace
* Overlay a sidebar video (optionally synchronized with input video)

## Getting started

On Windows:

* [Download](https://ffmpeg.zeranoe.com/builds/) a Windows build of ffmpeg and
  place the `ffmpeg.exe` binary in the repository root.
* There are various ways to get a Bash shell on Windows.
  [Git](https://git-scm.com/downloads) installs Bash and has Windows Explorer
  integration. The Windows Subsystem for Linux on Windows 10 also works.

Run `./encode.sh -h` for a list of options and other documentation.
