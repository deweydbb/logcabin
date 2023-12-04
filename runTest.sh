#!/bin/bash

NUM_TESTS=5
HOST_FILES=("hosts3.txt" "hosts5.txt" "hosts7.txt" "hosts9.txt")

for HOST_FILE in "${HOST_FILES[@]}"; do 
    echo "STARTING TESTS WITH HOST FILE $HOST_FILE"
    HOSTS=($(cat "$HOST_FILE" | tr "\n" " "))
    NUM_HOSTS="${#HOSTS[@]}"

    TEST_TIMES=()

    for TEST_NUM in $(seq 1 $NUM_TESTS); do
        printf "\tSTART OF TEST $TEST_NUM\n"
        # create a new cluster
        ./runRemote.sh --file "$HOST_FILE" > /dev/null 2>&1

        # wait for entire cluster to startup/join
        sleep 3

        ALL_SERVERS=""
        NEW_CONFIG=()

        # Loop through the array
        for INDEX in "${!HOSTS[@]}"
        do
            ID=$((INDEX + 1))
            NEW_ID=$(($ID+$NUM_HOSTS))
            HOST="${HOSTS[$INDEX]}"
            printf "\t\tCreating server $NEW_ID on $HOST\n"
            PORT=$((5254+$INDEX))
            NEW_PORT=$(($PORT+$NUM_HOSTS))
            echo "serverId = $NEW_ID" > "logcabin-$NEW_ID.conf"
            echo "listenAddresses = $HOST:$NEW_PORT" >> "logcabin-$NEW_ID.conf" 
            scp "logcabin-$NEW_ID.conf" "ec2-user@$HOST:/home/ec2-user/logcabin/logcabin-$NEW_ID.conf" > /dev/null 2>&1

            if [ "$INDEX" -eq "0" ]; then
                ALL_SERVERS="$HOST:$PORT,$HOST:$NEW_PORT"
                ssh -f "ec2-user@${HOST}" "sh -c 'cd /home/ec2-user/logcabin/; ./build/LogCabin --config logcabin-$ID.conf --bootstrap > stdout-log_${ID}_boot.log 2>&1'"
                sleep 1
            else 
                ALL_SERVERS="$ALL_SERVERS,$HOST:$PORT,$HOST:$NEW_PORT"
            fi
            NEW_CONFIG+=("$HOST:$NEW_PORT")

            ssh -f "ec2-user@${HOST}" "sh -c 'cd /home/ec2-user/logcabin/; nohup ./build/LogCabin --config logcabin-$NEW_ID.conf > stdout-log_$NEW_ID.log 2>&1 &'"
            sleep 1
        done

        # do reconfigure to add servers to cluster 
        printf "\t\tAbout to reconfigure\n"
        START_TIME=$(date +%s%N)
        ./build/Examples/Reconfigure --cluster=$ALL_SERVERS set "${NEW_CONFIG[@]}" > /dev/null 2>&1
        END_TIME=$(date +%s%N)



        # calculate difference between timestamps and convert to milliseconds
        DIFF=$(bc <<< "$END_TIME - $START_TIME")
        MS=$(bc <<< "$DIFF / 1000000")
        printf "\tMS: $MS\n"
        TEST_TIMES+=("$MS")

        # kill off cluster
        ./runRemoteKillServer.sh --file "$HOST_FILE" > /dev/null 2>&1
        sleep 2

        printf "END OF TEST $TEST_NUM\n"
    done

    TOTAL="0"
    for (( TEST_NUM=0; TEST_NUM<$NUM_TESTS; TEST_NUM++ ))
    do
        TOTAL=$(bc <<< "${TEST_TIMES[$TEST_NUM]} + $TOTAL")
    done

    echo "TOTAL: $TOTAL"

    AVG=$(bc <<< "$TOTAL / $NUM_TESTS")

    echo "AVG for $NUM_HOSTS hosts: $AVG"

done