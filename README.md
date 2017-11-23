# Video scripts

Shell scripts for editing videos with ffmpeg.

* Cut
* Crop
* Resize
* Deinterlace
* Overlay a sidebar video (optionally synchronized with input video)
* Concatenate

## Getting started

On Windows:

* [Download](https://ffmpeg.zeranoe.com/builds/) a Windows build of ffmpeg and
  place the `ffmpeg.exe` binary in the repository root.
* There are various ways to get a Bash shell on Windows.
  [Git](https://git-scm.com/downloads) installs Bash and has Windows Explorer
  integration. The Windows Subsystem for Linux on Windows 10 also works.

Run `./encode.sh -h` or `./concat.sh -h` for a list of options and other
documentation.

## Examples

Cut a video starting at 1:00 and ending at 3:00:

```shell
./encode.sh -s 1:00 -e 3:00 input.mp4
```

Crop a video (5px left/right, 10px top/bottom):

```shell
./encode.sh -c 5 10 5 10 input.mp4
```

Resize a video to 720p:

```shell
./encode.sh -r 720 input.mp4
```

Resize multiple videos to 720p:

```shell
./encode.sh -r 720 input1.mp4 input2.mp4 input3.mp4
```

Resize multiple videos to different sizes:

```shell
./encode.sh -r 720 input1.mp4 input2.mp4 -r 1080 input3.mp4 input4.mp4
```

Deinterlace a video:

```shell
./encode.sh -d input.mp4
```

Overlay a sidebar video on top of a video:

```shell
./encode.sh -b sidebar.mp4 input.mp4
```

Synchronize a sidebar video: let's say each video has some specific start point
and you want both videos to start at the same time. If the sidebar video starts
at 0:10 and the input video starts at 0:05, this would cut the sidebar video as
needed so that both videos start at 0:05.

```shell
./encode.sh -b sidebar.mp4 -t 5 10 input.mp4
```

Concatenate multiple videos into one video:

```shell
./concat.sh input1.mp4 input2.mp4 input3.mp4
```
