#!/bin/bash

while [[ $# -gt 0 ]]; do
  case $1 in
    --file)
      FILE="$2"
      shift
      shift
      ;;
    --help)
      echo "Options:"
      printf "--file Required. Specifies a file containing a list on hosts, one on each line to run addServer on\n"
      exit
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

if [[ -n ${FILE+x} ]]; then
  readarray -t HOSTS < "$FILE"
  NUM_HOSTS="${#HOSTS[@]}"
else
  echo "--file is required"
  exit
fi

echo "Performing cleanup"
./runRemoteCleanup.sh --file "$FILE" > /dev/null 2>&1

ALL_SERVERS=""
NEW_CONFIG=()

# Loop through the array
for INDEX in "${!HOSTS[@]}"
do
    ID=$((INDEX + 1))
    HOST="${HOSTS[$INDEX]}"
    echo "Creating server $ID on $HOST"
    PORT=$((5254+$INDEX))
    echo "serverId = $ID" > "logcabin-$ID.conf"
    echo "listenAddresses = $HOST:$PORT" >> "logcabin-$ID.conf" 
    scp "logcabin-$ID.conf" "ec2-user@$HOST:/home/ec2-user/logcabin/logcabin-$ID.conf"

    if [ "$INDEX" -eq "0" ]; then
        ALL_SERVERS="$HOST:$PORT"
        ssh -f "ec2-user@${HOST}" "sh -c 'cd /home/ec2-user/logcabin/; ./build/LogCabin --config logcabin-$ID.conf --bootstrap > stdout-log_${ID}_boot.log 2>&1'"
        sleep 1
    else 
        ALL_SERVERS="$ALL_SERVERS,$HOST:$PORT"
    fi
    NEW_CONFIG+=("$HOST:$PORT")

    ssh -f "ec2-user@${HOST}" "sh -c 'cd /home/ec2-user/logcabin/; nohup ./build/LogCabin --config logcabin-$ID.conf > stdout-log_$ID.log 2>&1 &'"
    sleep 1
done

# do reconfigure to add servers to cluster 
./build/Examples/Reconfigure --cluster=$ALL_SERVERS set "${NEW_CONFIG[@]}"