**用户指南：从照片中提取 GPS 坐标并导入 Dawarich**

> [English](../How_to_extract_geodata_from_photos.md)

简介：
本指南将手把手教你如何从照片中提取 GPS 坐标，并将其导入 Dawarich 服务。
当 Google 位置历史记录不可用，或者你当初没有开启它时，这个方法可以帮你把有纪念意义地点的照片，转换成位置点补充进 Dawarich。

前置要求：
- Mac OS 操作系统
- 已安装 exiftool 软件
- 已创建 exiftool 模板

将 GPS 坐标导入 Dawarich 的步骤：

1. 从[官方网站](https://exiftool.org/)下载并安装 exiftool。
2. 新建一个空白模板文本文件，命名为 `gpx.fmt`，并将下面的代码粘贴进去。
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
3. 为要提取坐标的照片单独创建一个目录。
4. 把需要的照片和 `gpx.fmt` 模板都移动到这个目录里。
5. 打开终端，进入存放照片的目录。

执行以下命令：
```
exiftool -if '$gpsdatetime' -fileOrder gpsdatetime -p ./gpx.fmt -d %Y-%m-%dT%H:%M:%SZ *JPG > output.gpx
```

注意：请确保系统上已正确安装 exiftool，并且 `gpx.fmt` 文件和照片位于同一目录下。

6. 基于照片 GPS 坐标和拍摄时间生成的 GPX 轨迹会以 `output.gpx` 文件的形式保存在同一目录中。
7. 打开 Dawarich 网页，进入"导入"页面，点击"新建导入"按钮，选择来源为 gpx，并选中 `output.gpx` 文件。
8. 导入处理完成后，所有 GPX 轨迹点都会被添加到 Dawarich 地图上。
