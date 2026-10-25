#!/usr/bin/env zsh
# Burns the captions in captions.tsv into raw.mp4 (recorded by demo.tape) and writes
#   ../docs/assets/demo.mp4  captioned video      ../docs/assets/demo.gif  captioned GIF for the README
#   ../docs/assets/demo.ja.vtt / demo.en.vtt / demo.ja.srt  subtitle tracks
# Needs ffmpeg (overlay filter only; no libass/freetype required) and ImageMagick.
emulate -L zsh -o err_exit -o pipe_fail
cd ${0:A:h}
local out=../docs/assets
local font=${CAPTION_FONT:-Hiragino-Sans-W6} work=$(mktemp -d)
local -a rows=(${(f)"$(grep -v '^#' captions.tsv)"})

# One rounded, gradient caption plate per line (pink -> violet, white text, soft shadow).
local i=0 row s e ja en
local -a inputs filters
for row in $rows; do
  IFS=$'\t' read -r s e ja en <<<$row
  (( ++i ))
  magick -background none -fill white -font $font -pointsize 38 label:$ja $work/t$i.png
  local w=$(magick identify -format %w $work/t$i.png) h=$(magick identify -format %h $work/t$i.png)
  local bw=$(( w + 72 )) bh=$(( h + 34 ))
  magick -size ${bw}x${bh} -define gradient:direction=east gradient:'#F472B6'-'#8B5CF6' \
    \( -size ${bw}x${bh} xc:none -fill white -draw "roundrectangle 0,0 $((bw-1)),$((bh-1)) 22,22" \) \
    -compose DstIn -composite $work/t$i.png -gravity center -compose Over -composite \
    \( +clone -background '#000000' -shadow 60x10+0+6 \) +swap -background none -layers merge +repage \
    $work/c$i.png
  inputs+=(-i $work/c$i.png)
  filters+=("[v$((i-1))][$i:v]overlay=x=(W-w)/2:y=H-h-64:enable='between(t,$s,$e)'[v$i]")
done

ffmpeg -v error -y -i raw.mp4 $inputs -filter_complex "[0:v]null[v0];${(j:;:)filters}" \
  -map "[v$i]" -c:v libx264 -pix_fmt yuv420p -crf 23 -preset slow -movflags +faststart $out/demo.mp4
ffmpeg -v error -y -i $out/demo.mp4 -vf "fps=12,scale=1080:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" $out/demo.gif

# Subtitle tracks.
ts() { local t=$1; printf '%02d:%02d:%02d%s%03d' $(( t / 3600 )) $(( t % 3600 / 60 )) $(( t % 60 )) $2 $(( (t * 1000) % 1000 )) }
{
  print WEBVTT; print
  for row in $rows; do IFS=$'\t' read -r s e ja en <<<$row; print "$(ts $s .) --> $(ts $e .)"; print -r -- $ja; print; done
} > $out/demo.ja.vtt
{
  print WEBVTT; print
  for row in $rows; do IFS=$'\t' read -r s e ja en <<<$row; print "$(ts $s .) --> $(ts $e .)"; print -r -- $en; print; done
} > $out/demo.en.vtt
i=0
{
  for row in $rows; do IFS=$'\t' read -r s e ja en <<<$row; (( ++i )); print $i; print "$(ts $s ,) --> $(ts $e ,)"; print -r -- $ja; print; done
} > $out/demo.ja.srt
command ls -la $out/demo.*
