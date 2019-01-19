#!/bin/bash

#title           volume_service.sh
#description     Service to set the volumee with help of LIRC.
#author          tjibbevanderlaan
#date            20181208
#version         0.2    
#usage           bash volume_service.sh
#==============================================================================

# Retrieve configuration file with variables
source volume_service.cfg

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

# Start the service
echo "Volume daemon is running. Waiting for incoming target..."
echo "current volume is $cur"

# Function to get the current time
function now() {
	echo $(date +%s%N)
}


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
			echo "move cursor from $cur to $dest"
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
				echo "target of $dest has been achieved"
				
				# Save the volume in file
				echo "save value"
				echo $cur > $saved_volume
				is_running=0
			fi
		fi
	fi
done
