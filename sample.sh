#!/bin/sh
#
dist_prefix=/someplace/
ipautil=/usr/local/bin/ipautil

# Copy command. cp, scp or install etc..
cp=cp

ipafile=$1
if [ "x$ipafile" == "x" ]; then
	echo "usage: sample.sh filename.ipa"
	exit 1
fi

# Extract CFBundleName (Application Name) from .ipa file
bundleName=`$ipautil -i CFBundleName $ipafile`

# Extract CFBundleVersion (Version) from .ipa file
bundleVersion=`$ipautil -i CFBundleVersion $ipafile`
date=`date '+%Y%m%d'`

# generate output path name
target=${dist_prefix}${bundleName}/${bundleName}-${date}-rel${bundleVersion}.ipa

echo "Coping file $ipafile to $target"
$cp $ipafile $target
