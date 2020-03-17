#!/bin/bash
#
# Attempts to convert a greenscreened video into a gif sticker
# automatically using a number of assumptions.
#
#

# constants
WORKDIR=/tmp/greenremover
CROPPERCENTAGE=10

# useful functions
function die {
	echo $@
	rm -r $WORKDIR
	exit 1
}

# check usage:
if [ "$#" != "4" ] ; then
	echo 'USAGE:'
	echo $0 '[input video]' '[output path]' '[spread]' '[corners]'
	echo
	echo '  input video is a video file you want turned into a sticker.'
	echo '  output path is where you want the file to go. Should be a .gif file.'
	echo '    Existing files at output path will be overwritten.'
	echo '  spread is how much variation in the background should be allowed.'
	echo '    Larger values will remove more pixels that look less like the'
	echo '    identified background. Start with a value of around 10 and increase'
	echo '    to remove more and decrease to remove less.'
	echo '  corners is a string contataining at least one of 1, 2, 3, and 4,'
	echo '    representing the four corners of the image. 1 is the top left,'
	echo '    and the rest continue clockwise. a portion of each corner is'
	echo '    sampled to determine what is background and should be removed.'
	echo '    Pick the corners that contain only background colors.'
	echo
	echo 'eg. to pick a background color by sampling the top right and bottom right'
	echo '  of a video called input.mp4, start with this command:'
	echo $0 input.mp4 out.gif 10 23
	echo 'This will output a file to the current directory called out.gif.'
	echo
	echo
	exit 1
fi

# give input vars better names:
input="${1}"
output="${2}"
spread="${3}"
corners="${4}"

# make a temporary working directory
rm -r $WORKDIR
mkdir $WORKDIR

# generate a first frame:
ff=${WORKDIR}/frame1.png
ffmpeg -i "$input" -vframes 1 -an -ss 0.0 $ff || die "could not build first frame"

# get the width and height:
width=`convert $ff -format "%w" info:`
height=`convert $ff -format "%h" info:`
left=$(( width - (CROPPERCENTAGE*width)/100 ))
bottom=$(( height - (CROPPERCENTAGE*height)/100 ))

#echo ===
#echo ${width}x${height}
#echo ${left}x${bottom}


# depending on the corners we've selected, crop the image and make sub-images.
if [[ $corners == *"1"* ]]; then
	# top left
	convert $ff -crop ${CROPPERCENTAGE}%x+0+0 ${WORKDIR}/crop1.png
fi
if [[ $corners == *"2"* ]]; then
	# top right
	convert $ff -crop ${CROPPERCENTAGE}%x+${left}+0 ${WORKDIR}/crop2.png
fi
if [[ $corners == *"3"* ]]; then
	# bottom right
	convert $ff -crop ${CROPPERCENTAGE}%x+${left}+${bottom} ${WORKDIR}/crop3.png
fi
if [[ $corners == *"4"* ]]; then
	# top left
	convert $ff -crop ${CROPPERCENTAGE}%x+0+${bottom} ${WORKDIR}/crop4.png
fi

#now montage the corners into one:
montage -geometry ${width}x${height}+0+0 -tile 1x ${WORKDIR}/crop?.png ${WORKDIR}/montage.png 

#get stats for the montaged image
fmt="%[fx:int(255*mean.r)] %[fx:int(255*standard_deviation.r)]"
fmt="$fmt %[fx:int(255*mean.g)] %[fx:int(255*standard_deviation.g)]"
fmt="$fmt %[fx:int(255*mean.b)] %[fx:int(255*standard_deviation.b)]"
fmt="$fmt %[fx:int(255*mean)] %[fx:int(255*standard_deviation)]"
		vals=(`convert ${WORKDIR}/montage.png -intensity average -format "${fmt}" info:-`)
		for i in 0 1 2 3 ; do
			ave[$i]=$(( ave[i] + vals[i*2] ))
			dev[$i]=$(( dev[i] + vals[i*2+1] ))
		done
		#echo ${vals[@]}
		#echo ${ave[@]}
		#echo ${dev[@]}
		#echo $count

# print a little debugging of our average and dev values:
echo    "		r	g	b	ave"
echo -n "average		"
for i in 0 1 2 3 ; do
	echo -n "${ave[$i]}	"
done
echo
echo -n "s dev		"
for i in 0 1 2 3 ; do
	echo -n "${dev[$i]}	"
done
echo

# now we are ready to take our original video and convert it to a transparent gif
# we do this in two passes: 1 to make a pallete, and 2 to make the actual gif.
hexcolor=$(printf "0x%02x%02x%02x" ${ave[0]} ${ave[1]} ${ave[2]})
[[ "${dev[3]}" == 0 ]] && dev[3]=1
similarity=$(echo "${dev[3]} * $spread / 255.0" | bc -l)
#scale="scale='trunc(min(1,min(720/iw,400/ih))*iw/2)*2':'trunc(min(1,min(720/iw,400/ih))*ih/2)*2'"
maxw=720
maxh=720
scale="scale='min(1,min($maxw/iw,$maxh/ih))*iw':'min(1,min($maxw/iw,$maxh/ih))*ih'"
chromakey="chromakey=$hexcolor:$similarity"
ffmpeg -v error -i "${input}" -filter_complex "[0:v]$scale,$chromakey[a];[a]palettegen[b]" -map "[b]" $WORKDIR/pallette.png || die "Can't make palette"
ffmpeg -v error -i "${input}" -i $WORKDIR/pallette.png -filter_complex "[0:v]$scale,$chromakey[trans];[trans][1:v]paletteuse[out]" -map "[out]" -y "$output" || die "can't make final video"

# clean our working directory
rm -r $WORKDIR
