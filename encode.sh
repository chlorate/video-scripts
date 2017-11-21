#!/bin/bash
set -o errexit -o nounset

input_path=""
output_path=""
sidebar_path=""

start=0
end=""
input_sync=""
sidebar_sync=""
crop=""
deinterlace=0
preset="medium"
audio_bitrate="320k"

width=852
height=480

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
				# Width is rounded to the nearest multiple of 4.
				validate_int "$2"
				width=$(echo "$2" | awk '{print int($1 * 16/9 / 4) * 4}')
				height="$2"
				shift 2
				;;
			-p|--preset)
				preset="$2"
				shift 2
				;;
			*)
				has_input=1
				input_path="$1"
				output_path="$(basename "${input_path%.*}").$preset.${height}p.mp4"
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
	echo "  $0 [options] input.avi"
	echo "  $0 [options] input1.avi [options] input2.avi ..."
	echo
	echo "Options:"
	echo "  -h, --help                                Help"
	echo "  -b, --sidebar <path>                      Add sidebar video"
	echo "  -t, --sync <input_time> <sidebar_time>    Times for syncing input and sidebar"
	echo "  -s, --start <time>                        Start time"
	echo "  -e, --end <time>                          End time"
	echo "  -c, --crop <left> <top> <right> <bottom>  Crop sides of input video"
	echo "  -d, --deinterlace                         Deinterlace input video"
	echo "  -r, --resize <height>                     Resize to certain height"
	echo "  -p, --preset <preset>                     x264 preset (default: medium)"
	echo
	echo "Time format:"
	echo "  Times must be in HH:MM:SS.ddd format. Only seconds are required."
	echo "  Examples: 1, 1.9, 1:23, 1:23.9, 1:23:45, 1:23:45.9"
	echo
	echo "Sidebar video:"
	echo "  When a sidebar video is given, the input video will be right-aligned and the"
	echo "  sidebar video will be overlaid and left-aligned. If sync times are given,"
	echo "  then the sidebar video will be synchronized such that the points in both "
	echo "  videos will happen at the same time."
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
	echo "$time" | awk -F ':' '{print $3, $2, $1}' | awk '{print $1 + $2*60 + $3*3600}'
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

# summary prints out a summary of the current settings.
summary() {
	echo "Input path:         $input_path"
	if [[ $sidebar_path ]]; then
		echo "Sidebar path:       $sidebar_path"
	fi
	echo "Output path:        $output_path"
	if [[ $start != 0 ]]; then
		echo "Start time:         $start"
	fi
	if [[ $end ]]; then
		echo "End time:           $end"
	fi
	if [[ $input_sync ]]; then
		echo "Input sync time:    $input_sync"
	fi
	if [[ $sidebar_sync ]]; then
		echo "Sidebar sync time:  $sidebar_sync"
	fi
	if [[ $deinterlace != 0 ]]; then
		echo "Deinterlace:        Yes"
	fi
	if [[ $crop ]]; then
		echo "Crop:               $crop"
	fi
	echo "Preset:             $preset"
	echo "Resolution:         $width x $height"
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
	if [[ $end ]]; then
		args+="-to $end "
	fi
	args+="-i \"$input_path\" "

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

		if [[ $input_sync && $sidebar_sync ]]; then
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

	args+="-preset $preset "
	args+="-crf 18 "
	args+="-b:a $audio_bitrate"

	cmd="./ffmpeg $args \"$output_path\""
	eval "$cmd"
	echo
}

parse_args $@
