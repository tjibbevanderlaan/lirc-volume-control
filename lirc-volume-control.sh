#!/bin/bash

#title           lirc-volume-control.sh
#description     Service to set the volumee with help of LIRC.
#author          tjibbevanderlaan
#date            20181208
#version         0.2    
#usage           bash lirc-volume-control.sh
#==============================================================================

# Retrieve configuration file with variables
source "/usr/local/bin/lirc-volume-control/lirc-volume-control.cfg"

cur=0
dest=0
dx=0

# Check if process is already running
if [[ -f $pidfile ]]; then
	echo "Volume daemon already running"
	exit 1
fi

# Create a file with current PID to indicate that process is running
echo $$ > "$pidfile"

# Open pipe to listen to new destination 
mkfifo $pipe -m=666

# Ensure pipe and PID file is removed on program exit.
function stop_service() {
	rm -f $pipe
	rm -f -- $pidfile
}
trap stop_service EXIT

# Get current volume, which is saved in a file
val=$(cat "$saved_volume")
if ! [[ "$val" -ge "$min_in_vol" && "$val" -le "$max_in_vol" ]]; then
	echo 0>$saved_volume
	val=0
fi
cur=$val
dest=$val

# Function to get the current time
function now() {
	echo $(date +%s%N)
}

# Start the service
echo "LIRC volume control is starting..."
echo "Calibrate volume from $cur to 0"
time=$(now)
interval=$((time+((sleep_per_step * cur) + 300) * 1000000))
irsend SEND_START $device $cmd_vol_down
while true
do
	time=$(now)
	if [[ "$time" -gt "$interval" ]]; then
		irsend SEND_STOP $device $cmd_vol_down
		echo "Calibrated to 0"
		break
	fi
done
if [[ "$cur" -gt "0" ]]; then
	echo "Move volume knob to saved volume $cur"
	time=$(now)
	interval=$((time+(sleep_per_step * cur * 1000000)))
	irsend SEND_START $device $cmd_vol_up
	while true
	do
		time=$(now)
		if [[ "$time" -gt "$interval" ]]; then
			irsend SEND_STOP $device $cmd_vol_up
			echo "Volume target of $cur has been achieved"
			break
		fi
	done
fi

# Listen for incoming updates
echo "LIRC volume control has been initialized."
echo "Waiting for incoming target..."
cmd=$cmd_vol_up
interval=$((sleep_per_step * 1000000)) # 100 ms
is_running=0

# Keep monitoring volume pipe
while true
do
	# Do we read new desitnatoin from pipe?
	read -t 0.002 line <>$pipe

	# Is the read return not empty and valid?
	if  [[ ! -z "$line" && "$line" -ge "$min_in_vol" && "$line" -le "$max_in_vol" ]]; then
		# check the current direction
		curdx=$((dest-cur))
		# insert the pipe dest
		dest=$line
		# add calibration procedure, if dest is 0
		if [[ "$dest" -eq "0" ]]; then
			dest=-10
		fi
		# check the new direction
		dx=$((dest-cur))
		# has the direction changed?
		changed_dx=$((curdx * dx))

		# if direction has changed, stop irsend
		echo "received $dest"
		if [[ changed_dx -lt 0 ]]; then
			echo "change direction to $dest"
			echo "irsend SEND_STOP" $device $cmd
			irsend SEND_STOP $device $cmd
			is_running=0
		elif [[ changed_dx -gt 0 ]]; then 
			echo "change goal to $dest"
			# update end time
			# time=$(now)
			# end_time=$((abs_destdx*sleep_per_step * 1000000+end_time))
		else
			echo "this happens"
		fi
	fi
	
	time=$(now)

	# Is the current volume not equal to the destination?
	if [[ "$cur" -ne "$dest" ]]; then
		# Than we need to update the current volume to the destination
		if [[ "$is_running" -eq 0 ]]; then
			echo "Move volume knob from $cur to $dest"
			dx=$((dest-cur))
			abs_dx=${dx#-}
			
			# determine whether we need to go up or down
			if [[ "$dx" -gt 0 ]]; then
				cmd=$cmd_vol_up
			elif [[ "$dx" -lt 0 ]]; then
				cmd=$cmd_vol_down
			fi

			# send commands
			echo $(date +%s%N)
			echo "irsend SEND_START" $device $cmd
			irsend SEND_START $device $cmd
			is_running=1
		fi

		# Is the time elapsed, than we passed one step to destination
		if [[ "$time" -gt "$((prev+interval))" ]]; then
			prev=$time
			if [[ "$dx" -gt 0 ]]; then
				cur=$((cur+1))
			elif [[ "$dx" -lt 0 ]]; then
				cur=$((cur-1))
			fi
			echo $cur

			# Is the current volume equal to destination?
			if [[ "$cur" -eq "$dest" ]]; then
				# We achieved the destination
				# Stop the sequence
				echo "irsend SEND_STOP" $device $cmd
				irsend SEND_STOP $device $cmd
				echo $(date +%s%N)
				echo "Volume target of $dest has been achieved"

				if [[ "$dest" -eq "-10" ]]; then
					cur=0
					dest=0
				fi
				
				# Save the volume in file
				echo "save value"
				echo $cur > $saved_volume
				is_running=0
			fi
		fi
	fi
done
