#!/bin/bash

# Example encoding a PB:
# ./encode.sh -d -s 15:52.685 -e 56:25 -b ./timer.mp4 -t 15:58.641,19.052 ../Capture/3423.avi

source='input.mp4'
sidebar_source=''
dest='output.mp4'
ext=''

crop=0
newCrop=''
deinterlace=0
start=0
sidebar_start=0
end=0
preset='medium'
audio_bitrate='320k'

width=852
height=480

input_param=''
filters_param=''
end_param=''

# usage displays help for this script's usage.
usage() {
	echo "$0 [options] input.avi"
	echo
	echo "Options:"
	echo "-h                           Help"
	echo "-s <time>                    Start time [[HH:]MM:]SS[.dd]"
	echo "-e <time>                    End time [[HH:]MM:]SS[.dd]"
	echo "-d                           Deinterlace and filter raw video"
	echo "-c                           Crop for MM9/MM10 (if -d is enabled)"
	echo "-C                           Crop sides (left,top,right,bottom)"
	echo "-b <path>                    Add sidebar video"
	echo "-t <gametime>,<sidebartime>  Specify when time starts in game and sidebar videos"
	echo "-r <height>                  Resize to certain height, maintaining aspect ratio (e.g., 360, 480, 720, 1080)"
	echo "-f                           Force aspect ratio of source to 16:9 (e.g., resizing 480p to 720p)"
	echo "-p <preset>                  Set preset (default is medium)"
	echo
	echo "During encoding, type q and then press Enter to stop encoding."
}

# to_seconds converts timestamps of the form [[HH:]MM:]SS[.dd] to the total
# number of seconds.
to_seconds() {
	echo "$1" | awk -F ':' '{print $3, $2, $1}' | awk '{print $1 + $2*60 + $3*3600}'
}

# to_crop_params converts an input string of the form "left,top,right,bottom"
# to the parameters accepted by ffmpeg's crop filter "w:h:x:y".
to_crop_params() {
	echo "$1" | awk -F ',' '{print "iw-" $1+$3 ":ih-" $2+$4 ":" $1 ":" $2}'
}

# add_filter appends a filter to a comma-separated string of filters. $1 is the
# current string, $2 is the filter to be appended, and the output is the
# concatenated filters.
add_filter() {
	if [[ $1 == '' || $2 == '' ]]
	then
		echo "$1$2"
		return
	fi
	echo "$1,$2"
}

# parse_args parses the command line arguments.
parse_args() {
	local filters=""
	local fixed_size=0

	while getopts 'hs:e:db:t:r:fp:cC:' opt; do
		case $opt in
			h)
				usage
				exit
				;;
			s)
				start=$(to_seconds $OPTARG)
				;;
			e)
				end=$(to_seconds $OPTARG)
				;;
			c)
				crop=1
				;;
			C)
				newCrop=$(to_crop_params $OPTARG)
				;;
			d)
				deinterlace=1
				;;
			b)
				sidebar_source=$OPTARG
				;;
			t)
				local game=$(to_seconds ${OPTARG%,*})
				local sidebar=$(to_seconds ${OPTARG##*,})
				sidebar_start=$(echo | awk "{print $sidebar - ($game - $start)}")
				;;
			r)
				width=$(echo "$OPTARG" | awk '{print int($1 * 16/9 / 4) * 4}')
				height=$OPTARG
				;;
			f)
				fixed_size=1
				;;
			p)
				preset=$OPTARG
				;;
		esac
	done

	if [[ $end != 0 ]]
	then
		end_param="-to $(echo | awk "{print $end - $start}")"
	fi
	if [[ $deinterlace != 0 ]]
	then
		filters=$(add_filter "$filters" 'yadif=1,mcdeint=parity=tff:qp=10')
	fi
	if [[ $crop != 0 ]]
	then
		# MM9/10 cropping
		if [[ $sidebar_source != '' ]]
		then
			filters=$(add_filter "$filters" 'crop=iw-56:ih-44:27:20')
		else
			filters=$(add_filter "$filters" 'crop=iw-56:ih-31:27:15')
		fi
	fi
	if [[ ! -z $newCrop ]]
	then
		filters=$(add_filter "$filters" "crop=$newCrop")
	fi

	shift $((OPTIND - 1))
	source="$@"
	ext="$preset.${height}p"
	dest=$(basename "${source%.*}").$ext.mp4

	if [[ $start != '' ]]
	then
		input_param="-ss $start"
	fi
	input_param="$input_param -i \"$source\""

	local scale="scale=$width:$height:force_original_aspect_ratio=decrease" # TODO: originally: -1:height with no force
	local pad="pad=$width:$height"
	if [[ $fixed_size != 0 ]]
	then
		scale="scale=$width:$height"
	fi

	if [[ $sidebar_source != '' ]]
	then
		# The documentation for the overlay filter recommends using the
		# setpts filter because of timestamping issues with the overlay
		# filter. Fixes the sidebar appearing a couple frames after the
		# video starts.
		local setpts="setpts=PTS-STARTPTS"

		# Align game video to right and overlay sidebar video on left.
		input_param+=" -ss $sidebar_start -i $sidebar_source"
		filters=$(add_filter "$setpts" "$filters")
		filters=$(add_filter "$filters" "$scale")
		filters=$(add_filter "$filters" "$pad:ow-iw:(oh-ih)/2")
		filters_param="-filter_complex \"[0:v:0]$filters[game];[1:v:0]$setpts,$scale[sidebar];[game][sidebar]overlay\""
	else
		# Centered game video.
		filters=$(add_filter "$filters" "$scale")
		filters=$(add_filter "$filters" "$pad:(ow-iw)/2:(oh-ih)/2")
		filters_param="-vf \"$filters\""
	fi
}

# summary prints out a summary of the current settings.
summary() {
	if [[ $sidebar_source != "" ]]
	then
		echo "Sidebar source:     $sidebar_source"
	fi
	echo "Destination:        $dest"
	echo "Preset:             $preset"
	echo "Resolution:         $width x $height"
	echo "Audio bitrate:      $audio_bitrate"

	if [[ $start != 0 ]]
	then
		echo "Start time:         $start"
	fi
	if [[ $sidebar_start != 0 ]]
	then
		echo "Sidebar start time: $sidebar_start"
	fi
	if [[ $end != 0 ]]
	then
		echo "End time:           $end"
	fi
	if [[ $deinterlace != 0 ]]
	then
		echo "Deinterlace and filter raw video"
	fi
	echo
}

# encode runs ffmpeg to encode the video.
encode() {
	echo "Source: $source"

	cmd="./ffmpeg $input_param $filters_param $end_param -preset $preset -crf 18 -b:a $audio_bitrate \"$dest\""
	eval "$cmd"
	echo "$cmd"
	echo
}

if [[ -z $@ ]]
then
	echo "No input file given (use -h for help)"
	exit
fi

parse_args $@
summary
encode


#  ./encode.sh -s 3:53.116 -e 41:01.926 -d -b timer.mp4 -t 4:07.564,25.842 -r ../Capture/3304.avi
#  ./encode.sh -s 40:21.653 -e 1:17:02.017 -d -b timer2.mp4 -t 40:36.718,29:796 -r ../Capture/3236.avi
