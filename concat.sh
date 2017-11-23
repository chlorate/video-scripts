#!/bin/bash
set -o errexit -o nounset

ffmpeg_path=""
list=""
list_path="list.tmp"
input_paths=""
output_path="out.mp4"

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
			-o|--output)
				output_path="$2"
				shift 2
				;;
			*)
				has_input=1
				list+="file '$1'\n"
				input_paths+="  $1\n"
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
	echo "  $0 [options] input1.mp4 input2.mp4 ..."
	echo
	echo "Options:"
	echo "  -h, --help           Help"
	echo "  -o, --output <path>  Set path to output file"
	echo
	echo "All input videos must be the same format."
}

# summary prints out a summary of the current settings.
summary() {
	echo "Input paths:"
	echo -en "$input_paths"
	echo "Output path: $output_path"
	echo
}

# concat runs ffmpeg to concatenate the videos.
concat() {
	echo -e "$list" > "$list_path"
	local cmd="$ffmpeg_path -f concat -safe 0 -i \"$list_path\" -c copy \"$output_path\""
	eval "$cmd"
	rm "$list_path"
}

find_ffmpeg
parse_args "$@"
summary
concat
