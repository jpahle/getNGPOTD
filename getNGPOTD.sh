#!/bin/bash

# Copyright (C) 2013 by Juergen Pahle. All rights reserved.

DIR=~/getNGPOTD/
IMAGE_FILE=NGPOTD.jpg
NGPOTD_URL=http://photography.nationalgeographic.com/photography/photo-of-the-day/

PREFIX0=0
PREFIX1=1

# error codes
E_USAGE=64
E_TEMPFILE=65
E_READFILE=66
E_DOWNLOAD_HTML=67
E_DOWNLOAD_WALLPAPER=68
E_DOWNLOAD_PICTURE=69
E_WRITE_DIR=70
E_WRITE=71
E_GCONFTOOL=72
E_OSASCRIPT=73
E_OS_NOT_KNOWN=74

# argument handling
if [[ $# -gt 1 ]] ; then
    echo "usage: $0 [file]" 1>&2
    exit $E_USAGE
fi

# get file from National Geographic webpage or use file given on command line
if [[ $# -eq 1 ]] ; then
  FILE=$(cat "$1" 2> /dev/null)
  if [[ ! -n $FILE ]] ; then echo "$0: could not read from file $1" 1>&2; exit $E_READFILE; fi
else
  FILE=$(curl -s $NGPOTD_URL 2> /dev/null)
  if [[ ! -n $FILE ]] ; then echo "$0: could not read from URL $NGPOTD_URL" 1>&2; exit $E_DOWNLOAD_HTML; fi
fi

# first try to extract link to wallpaper version
LINK=$(printf '%s' "$FILE" | sed -n 's/.*<div class=\"download_link\"><a href=\"\(.*\)\">Download Wallpaper.*/\1/p' | sed -n 's/^\/*//p')

# create temporary file
TEMPFILE=$(mktemp $DIR/temp_$IMAGE_FILE.XXXXXX)
if [[ $? -ne 0 ]] ; then echo "$0: could not create temporary file" 1>&2; exit $E_TEMPFILE; fi

trap "E_TRAP=$?; rm -f $TEMPFILE; exit $E_TRAP" INT TERM EXIT

# if link could be extracted download wallpaper version
if [[ "$LINK" != "" ]] ; then
  curl -s -o "$TEMPFILE" "$LINK" 2> /dev/null || { echo "$0: could not download wallpaper version from $LINK" 1>&2; exit $E_DOWNLOAD_WALLPAPER; }
# if not download (lower resolution) version from NG webpage
else
  LINK=$(printf '%s' "$FILE" | sed -n '/<div class=\"primary_photo\">/,/<\/div>/ s/.*<img src=\"\(.*jpg\).*/\1/p' | sed -n 's/^\/*//p')
  curl -s -o "$TEMPFILE" "$LINK" 2> /dev/null || { echo "$0: could not download lower resolution version from $LINK" 1>&2; exit $E_DOWNLOAD_PICTURE; }
fi

# save picture to 0/1NGPOTD.jpg
if [[ ! -w "$DIR" ]] ; then echo "$0: do not have write permissions for directory $DIR" 1>&2; exit $E_WRITE_DIR; fi
if [[ -e "$DIR$PREFIX0$IMAGE_FILE" ]] ; then
    rm "$DIR$PREFIX0$IMAGE_FILE"
    IMAGE_FILE="$PREFIX1$IMAGE_FILE"
elif [[ -e "$DIR$PREFIX1$IMAGE_FILE" ]] ; then
    rm "$DIR$PREFIX1$IMAGE_FILE"
    IMAGE_FILE="$PREFIX0$IMAGE_FILE"
else
    IMAGE_FILE="$PREFIX0$IMAGE_FILE"
fi
mv $TEMPFILE "$DIR$IMAGE_FILE" || { echo "$0: could not write to $DIR$IMAGE_FILE" 1>&2; exit $E_WRITE; }

trap - INT TERM EXIT

if [[ $(uname) == 'Linux' ]] ; then
  # Linux: update Gnome background
  gconftool-2 -t str -s /desktop/gnome/background/picture_filename "$DIR$IMAGE_FILE" || { echo "$0: could not set background image with gconftool-2 ($DIR$IMAGE_FILE)" 1>&2; exit $E_GCONFTOOL; }
elif [[ $(uname) == 'Darwin' ]] ; then
  # Mac OS: refresh desktop background to show new 0/1NGPOTD.jpg
  /usr/bin/osascript <<EOFOSA
tell application "Finder"
  set pFile to POSIX file "$DIR$IMAGE_FILE" as string
  set desktop picture to file pFile
  end tell
EOFOSA
  if [[ $? -ne 0 ]] ; then echo "$0: could not set background image using osascript ($DIR$IMAGE_FILE)" 1>&2; exit $E_OSASCRIPT; fi
else
  echo "$0: does not support OS ($(uname))"
  exit $E_OS_NOT_KNOWN
fi
