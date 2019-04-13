#!/bin/bash
pipe="/tmp/lirc-volume-pipe"
vol=$(echo "(($1+30)*2)/1" | bc)
if [[ "$vol" -lt 0 ]]; then
        vol=0
fi
echo $vol
echo $vol >> $pipe

