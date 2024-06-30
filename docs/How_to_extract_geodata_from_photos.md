**User Guide: Importing GPS Coordinates from your photos into Dawarich**

Introduction:
This user guide provides step-by-step instructions on how to extract GPS coordinates from photos and import it into the Dawarich service.
This process is useful for adding points of interest from memorable locations into Dawarich, especially when Google Location History is unavailable or was not initially enabled.

Requirements:
- Mac OS operating system
- exiftool software installed
- exiftool template created

Steps to Import GPS Coordinates into Dawarich:

1. Download and install exiftool from the [official website](https://exiftool.org/).
2. Create an empty template text file, name it as `gpx.fmt` and paste the code provided below into it.
```
#------------------------------------------------------------------------------
# File:         gpx.fmt
#
# Description:  Example ExifTool print format file to generate a GPX track log
#
# Usage:        exiftool -p gpx.fmt -ee3 FILE [...] > out.gpx
#
# Requires:     ExifTool version 10.49 or later
#
# Revisions:    2010/02/05 - P. Harvey created
#               2018/01/04 - PH Added IF to be sure position exists
#               2018/01/06 - PH Use DateFmt function instead of -d option
#               2019/10/24 - PH Preserve sub-seconds in GPSDateTime value
#
# Notes:     1) Input file(s) must contain GPSLatitude and GPSLongitude.
#            2) The -ee3 option is to extract the full track from video files.
#            3) The -fileOrder option may be used to control the order of the
#               generated track points when processing multiple files.
#------------------------------------------------------------------------------
#[HEAD]<?xml version="1.0" encoding="utf-8"?>
#[HEAD]<gpx version="1.0"
#[HEAD] creator="ExifTool $ExifToolVersion"
#[HEAD] xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
#[HEAD] xmlns="http://www.topografix.com/GPX/1/0"
#[HEAD] xsi:schemaLocation="http://www.topografix.com/GPX/1/0 http://www.topografix.com/GPX/1/0/gpx.xsd">
#[HEAD]<trk>
#[HEAD]<number>1</number>
#[HEAD]<trkseg>
#[IF]  $gpslatitude $gpslongitude
#[BODY]<trkpt lat="$gpslatitude#" lon="$gpslongitude#">
#[BODY]  <ele>$gpsaltitude#</ele>
#[BODY]  <time>${gpsdatetime#;my ($ss)=/\.\d+/g;DateFmt("%Y-%m-%dT%H:%M:%SZ");s/Z/${ss}Z/ if $ss}</time>
#[BODY]</trkpt>
#[TAIL]</trkseg>
#[TAIL]</trk>
#[TAIL]</gpx>
```
3. Create a separate directory for the photos from which you want to extract coordinates.
4. Move the necessary photos and `gpx.fmt` template to this directory.
5. Open Terminal and navigate to the directory containing the photos.

Command to Execute:
```
exiftool -if '$gpsdatetime' -fileOrder gpsdatetime -p ./gpx.fmt -d %Y-%m-%dT%H:%M:%SZ *JPG > output.gpx
```

Note: Ensure that exiftool is properly installed on your system, and the file 'gpx.fmt' is located in the same directory as the photos.

6. GPX-track based on photo's GPS-coordinates and dates will be placed as `output.gpx` file into the same directory.
7. Go to Dawarich webpage, select Imports, click "New Import" button, select source — gpx and choose `output.gpx` file.
8. After the import processed all GPX-points will be added to Dawarich map.
