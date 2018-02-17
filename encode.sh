#!/bin/bash
set -o errexit -o nounset

ffmpeg_path=""
input_path=""
sidebar_path=""
output_path=""

start=0
end=0
input_sync=0
sidebar_sync=0
crop=""
deinterlace=0
resize=0
extension="mp4"
preset="veryfast"
crf=0
audio_bitrate="320k" # TODO: Test lower values. Originally set high to fix glitchy audio output.

width=0
height=0

# find_ffmpeg determines the path to ffmpeg.
find_ffmpeg() {
	if [[ -x "./ffmpeg.exe" ]]; then
		ffmpeg_path="./ffmpeg.exe"
	elif command -v ffmpeg > /dev/null 2>&1; then
		ffmpeg_path="ffmpeg"
	else
		echo "Cannot find ffmpeg executable"
		exit 1
	fi
}

# parse_args parses the command line arguments.
parse_args() {
	local has_input=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h|--help)
				usage
				exit
				;;
			-b|--sidebar)
				sidebar_path="$2"
				shift 2
				;;
			-t|--sync)
				validate_time "$2"
				validate_time "$3"
				input_sync=$(time_to_seconds "$2")
				sidebar_sync=$(time_to_seconds "$3")
				shift 3
				;;
			-s|--start)
				validate_time "$2"
				start=$(time_to_seconds "$2")
				shift 2
				;;
			-e|--end)
				validate_time "$2"
				end=$(time_to_seconds "$2")
				shift 2
				;;
			-c|--crop)
				crop="$2 $3 $4 $5"
				validate_crop
				shift 5
				;;
			-d|--deinterlace)
				deinterlace=1
				shift
				;;
			-r|--resize)
				validate_int "$2"
				resize="$2"
				shift 2
				;;
			-w|--webm)
				extension="webm"
				shift
				;;
			-p|--preset)
				preset="$2"
				shift 2
				;;
			*)
				has_input=1
				input_path="$1"
				if [[ ! -f "$input_path" ]]; then
					echo "File not found: $input_path"
					exit 1
				fi
				set_dimensions
				set_crf
				set_output_path
				summary
				encode
				shift
				;;
		esac
	done

	if [[ $has_input = 0 ]]; then
		echo "No input files given (use -h for help)"
		exit 1
	fi
}

# usage displays help for this script's usage.
usage() {
	echo "Usage:"
	echo "  $0 [options] input.mp4"
	echo "  $0 [options] input1.mp4 [options] input2.mp4 ..."
	echo
	echo "Options:"
	echo "  -h, --help                                Help"
	echo "  -b, --sidebar <path>                      Add sidebar video"
	echo "  -t, --sync <input_time> <sidebar_time>    Sync input and sidebar videos"
	echo "  -s, --start <time>                        Start time"
	echo "  -e, --end <time>                          End time"
	echo "  -c, --crop <left> <top> <right> <bottom>  Crop sides of input video"
	echo "  -d, --deinterlace                         Deinterlace input video"
	echo "  -r, --resize <height>                     Resize to certain height"
	echo "  -w, --webm                                Output webm (VP9) instead of mp4 (H.264)"
	echo "  -p, --preset <preset>                     x264 preset for mp4 (default: veryfast)"
	echo
	echo "Time format:"
	echo "  Times must be in HH:MM:SS.ddd format. Only seconds are required."
	echo "  Examples: 1, 1.9, 1:23, 1:23.9, 1:23:45, 1:23:45.9"
	echo
	echo "Sidebar video:"
	echo "  When a sidebar video is given, the input video will be right-aligned and the"
	echo "  sidebar video will be overlaid and left-aligned. If sync times are given,"
	echo "  then the sidebar video will be cropped or delayed such that a certain frame"
	echo "  in both videos will play at the same time."
	echo
	echo "Resizing:"
	echo "  The output video is always 16:9. If the input video is not, then its aspect"
	echo "  ratio will be maintained and it is centered and padded with black bars."
	echo
	echo "Press q<Enter> to stop encoding the current file."
}

# validate_crop exits with an error if the crop value is not valid.
validate_crop() {
	if [[ ! "$crop" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]]; then
		echo "Invalid crop: $crop"
		exit 1
	fi
}

# validate_int exits with an error if a value is not an integer.
validate_int() {
	local value="$1"
	if [[ ! "$value" =~ ^[0-9]+$ ]]; then
		echo "Invalid integer: $value"
		exit 1
	fi
}

# validate_time exits with an error if a value is not a time.
validate_time() {
	local value="$1"
	if [[ ! "$value" =~ ^([0-9]+:)?([0-9]+:)?[0-9]+(\.[0-9]+)?$ ]]; then
		echo "Invalid time: $value"
		exit 1
	fi
}

# time_to_seconds converts a time string in the form HH:MM:SS.ddd to a total
# number of seconds.
time_to_seconds() {
	local time="$1"
	echo "$time" | awk --field-separator ":" '{print $3, $2, $1}' | awk '{print $1 + $2*60 + $3*3600}'
}

# seconds_to_time converts a number of seconds to HH:MM:SS.ddd format.
seconds_to_time() {
	local seconds="$1"
	local script='{
		if ($1 >= 3600) {
			printf "%d:%02d:%06.3f", int($1 / 3600), int($1 % 3600 / 60), $1 % 60
		} else if ($1 >= 60) {
			printf "%d:%06.3f", int($1 / 60), $1 % 60
		} else {
			printf "%.3f", $1
		}
	}'
	echo "$seconds" | awk "$script" | sed 's/0\+$//;s/\.$//'
}

# add_filter appends a filter to a comma-separated string of filters. $1 is the
# current string, $2 is the filter to be appended, and the output is the
# concatenated filters.
add_filter() {
	if [[ -z $1 || -z $2 ]]; then
		echo "$1$2"
	else
		echo "$1,$2"
	fi
}

# set_dimensions sets the dimensions of the output video. 16:9 aspect ratio will
# be used. If the resize argument was given, then the dimensions will be based
# on that. Otherwise, the same dimensions of the input video will be used.
set_dimensions() {
	if [[ $resize != 0 ]]; then
		height="$resize"
	else
		# Extract video height from ffmpeg's output. Need to ignore hex values
		# that start with "0x".
		height=$("$ffmpeg_path" -i "$input_path" 2>&1 | \
			grep --only-matching "[0-9]\+x[0-9]\+" | \
			awk --field-separator "x" '$1 > 0 { print $2; exit }')
	fi

	# Round width down to nearest multiple of 4.
	width=$(echo "$height" | awk '{print int($1 * 16/9 / 4) * 4}')
}

# set_crf sets the CRF value used for encoding based on the output format and
# video height.
set_crf() {
	if [[ $extension == "mp4" ]]; then
		crf=18
	elif [[ $extension == "webm" ]]; then
		# CRF values taken from:
		# https://developers.google.com/media/vp9/settings/vod/#recommended_settings
		if [[ $height -gt 1440 ]]; then
			crf=15
		elif [[ $height -gt 1080 ]]; then
			crf=24
		elif [[ $height -gt 720 ]]; then
			crf=31
		elif [[ $height -gt 480 ]]; then
			crf=32
		else
			crf=33
		fi
	fi
}

# set_output_path sets the path of the output video based on the input path and
# current settings.
set_output_path() {
	output_path="$(basename "${input_path%.*}")."
	if [[ $extension == "mp4" ]]; then
		output_path+="$preset."
	fi
	output_path+="${height}p.${extension}"
}

# summary prints out a summary of the current settings.
summary() {
	echo "Input path:         $input_path"
	if [[ $sidebar_path ]]; then
		echo "Sidebar path:       $sidebar_path"
	fi
	echo "Output path:        $output_path"
	if [[ $start != 0 ]]; then
		echo "Start time:         $(seconds_to_time $start)"
	fi
	if [[ $end != 0 ]]; then
		echo "End time:           $(seconds_to_time $end)"
	fi
	if [[ $sidebar_path && $input_sync != 0 ]]; then
		echo "Input sync time:    $(seconds_to_time $input_sync)"
	fi
	if [[ $sidebar_path && $sidebar_sync != 0 ]]; then
		echo "Sidebar sync time:  $(seconds_to_time $sidebar_sync)"
	fi
	if [[ $deinterlace != 0 ]]; then
		echo "Deinterlace:        Yes"
	fi
	if [[ $crop ]]; then
		echo "Crop:               $crop"
	fi
	echo "CRF:                $crf"
	if [[ $extension == "mp4" ]]; then
		echo "Preset:             $preset"
	fi
	echo "Resolution:         $width × $height"
	echo "Audio bitrate:      $audio_bitrate"
	echo
}

# encode runs ffmpeg to encode the video.
encode() {
	local args=""
	local filters=""

	if [[ $start != 0 ]]; then
		args+="-ss $start "
	fi
	if [[ $end != 0 ]]; then
		args+="-to $end "
	fi
	args+="-i \"$input_path\" "
	if [[ $extension == "webm" ]]; then
		# Doesn't seem to use multiple threads by default.
		args+="-c:v libvpx-vp9 -threads 0 "
	fi

	if [[ $deinterlace != 0 ]]; then
		filters=$(add_filter "$filters" "yadif=1,mcdeint=parity=tff:qp=10")
	fi
	if [[ $crop ]]; then
		local params=$(echo "$crop" | awk '{print "iw-" $1+$3 ":ih-" $2+$4 ":" $1 ":" $2}')
		filters=$(add_filter "$filters" "crop=$params")
	fi

	local scale="scale=$width:$height:force_original_aspect_ratio=decrease"
	filters=$(add_filter "$filters" "$scale")

	local pad="pad=$width:$height"
	if [[ $sidebar_path ]]; then
		# The documentation for the overlay filter recommends using the
		# setpts filter because of timestamping issues with the overlay
		# filter. Fixes the sidebar appearing a couple frames after the
		# video starts.
		# Source: https://www.ffmpeg.org/ffmpeg-filters.html#overlay-1
		local setpts="setpts=PTS-STARTPTS"
		filters=$(add_filter "$setpts" "$filters")

		if [[ $input_sync != 0 || $sidebar_sync != 0 ]]; then
			args+="-ss $(awk "BEGIN { print $sidebar_sync - ($input_sync - $start)}") "
		fi
		args+="-i $sidebar_path "

		# Align input video to right and overlay sidebar video on left.
		filters=$(add_filter "$filters" "$pad:ow-iw:(oh-ih)/2")
		args+="-filter_complex \"[0:v:0]$filters[input];[1:v:0]$setpts,$scale[sidebar];[input][sidebar]overlay\" "
	else
		# Centered input video.
		filters=$(add_filter "$filters" "$pad:(ow-iw)/2:(oh-ih)/2")
		args+="-vf \"$filters\" "
	fi

	if [[ $extension == "mp4" ]]; then
		args+="-preset $preset "
	elif [[ $extension == "webm" ]]; then
		args+="-b:v 0 " # Enables Constant Quality mode.
	fi
	args+="-crf $crf "
	args+="-b:a $audio_bitrate"

	local cmd="$ffmpeg_path $args \"$output_path\""
	eval "$cmd"
	echo
}

find_ffmpeg
parse_args "$@"
