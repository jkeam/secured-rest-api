#!/bin/bash

LOG_FILE=$(basename "$0")
LOG_FILE="${LOG_FILE%.*}".log

#__functions___________________________________________________

function usage
{
    echo "Usage: $0 [(--instance|-i) <instance>] [(--maxWait|-m) <seconds>] [(--goal|-g) <goal>] [(--shardCheck|-s) <true|false>] [--mirrorCheck <true|false>] [--productionCheck|-p <true|false>] [--iscAgentCheck <true|false>]"
}

#__options___________________________________________________

while [ "$1" != "" ]; do
    case $1 in
        --instance|-i )
            shift
            iscInstance=$1
            ;;
        --maxWait|-m )
            shift
            if [[ $1 =~ ^[0-9]+$ ]]; then
                maxWait=$1
            else
                echo "Error: Wait time '$1' is not a number" 1>&2
                exit 1
            fi
            ;;
        --goal|-g )
            shift
            goal=$1
            ;;
        --shardCheck|-s )
            shift
            if [[ $1 =~ ^(true|false)$ ]]; then
                shardCheck=$1
            else
                echo "Error: Shard check '$1' is invalid (expected 'true' or 'false')" 1>&2
                exit 1
            fi
            ;;
        --mirrorCheck )
            shift
            if [[ $1 =~ ^(true|false)$ ]]; then
                mirrorCheck=$1
            else
                echo "Error: Mirror check '$1' is invalid (expected 'true' or 'false')" 1>&2
                exit 1
            fi
            ;;
        --productionCheck|-p )
            shift
            if [[ $1 =~ ^(true|false)$ ]]; then
                productionCheck=$1
            else
                echo "Error: Production check '$1' is invalid (expected 'true' or 'false')" 1>&2
                exit 1
            fi
            ;;
        --iscAgentCheck )
            shift
            if [[ $1 =~ ^(true|false)$ ]]; then
                iscAgentCheck=$1
            else
                echo "Error: ISCAgent check '$1' is invalid (expected 'true' or 'false')" 1>&2
                exit 1
            fi
            ;;
        *)
            echo Error: Unrecognized option \"$1\" 1>&2
            usage
            exit 1
            ;;
    esac
    shift
done

#__defaults___________________________________________________

if [ -z "$iscInstance" ] ; then
    iscInstance=$ISC_PACKAGE_INSTANCENAME
    if [ -z "$iscInstance" ] ; then
        iscInstance=IRIS
    fi
    echo "InterSystems IRIS instance not specified; using '$iscInstance'" |& tee -a $LOG_FILE
fi

if [ -z "$maxWait" ]; then
    maxWait=300
    echo "Wait time not specified; using $maxWait" |& tee -a $LOG_FILE
fi

# maxWait/10 more than sufficient
qlistWait=$(($maxWait/10 > 0 ? maxWait/10 : 1))

if [ -z "$goal" ]; then
    goal="running"
    echo "Goal state not specified; using '$goal'" |& tee -a $LOG_FILE
fi

if [ -z "$shardCheck" ]; then
    shardCheck="true"
    echo "Sharding check not specified; using '$shardCheck'" |& tee -a $LOG_FILE
fi

if [ -z "$mirrorCheck" ]; then
    mirrorCheck="true"
    echo "Mirror check not specified; using '$mirrorCheck'" |& tee -a $LOG_FILE
fi

if [ -z "$productionCheck" ]; then
    productionCheck="true"
    echo "Production check not specified; using '$productionCheck'" |& tee -a $LOG_FILE
fi

if [ -z "$iscAgentCheck" ]; then
    iscAgentCheck="true"
    echo "ISCAgent check not specified; using '$iscAgentCheck'" |& tee -a $LOG_FILE
fi

#__body___________________________________________________

# verify InterSystems IRIS up and running
duration=0
start=$(date +%s)
now=start
while [ 1 ]; do
    line=$(timeout --signal=SIGKILL $qlistWait iris qlist $iscInstance 2>&1)
    case $? in
        0)
            state=$(echo $line | cut -d '^' -f4 | cut -d ',' -f1)
            status=$(echo $line | cut -d '^' -f9)
            reason="Reason unknown"
            if [ "$state" == "$goal" ]; then
                success=1
                if [ "$goal" == "running" ]; then
                    # check for hung instance
                    if [ "$status" == "hung" ]; then
                        reason="Instance is hung"
                        success=0
                    fi
                    # wait for startup to complete
                    if [ "$(pidof "iris-main")" ]; then
                        if [ -a "$(pidof "irisstart")" ]; then
                            reason="Startup underway"
                            success=0
                        fi
                    fi
                fi
                if [ "$success" -gt 0 ]; then
                    now=$(date +%s)
                    duration=$(( $now - $start ))
                    echo -e "\nWaited $duration seconds for InterSystems IRIS to reach state '$goal'" |& tee -a $LOG_FILE
                    break
                fi
            fi
            ;;
        124 | 137)
            # call timed out
            echo -e "\nCall to 'iris qlist' timed out after $qlistWait seconds" |& tee -a $LOG_FILE
            ;;
        *)
            # unknown error
            echo -e "\nCall to 'iris qlist' exited with status $?" |& tee -a $LOG_FILE
            ;;
    esac
    now=$(date +%s)
    duration=$(( $now - $start ))
    if [ "$duration" -gt "$maxWait" -a "$maxWait" -gt 0 ]; then
        echo -e "\nInterSystems IRIS took longer than $maxWait seconds to reach state '$goal': $reason" |& tee -a $LOG_FILE 1>&2
        exit 1
    fi
    echo -n . |& tee -a $LOG_FILE
    sleep 1
done

# used by checks that follow
mirrortype=$(echo $line | cut -d '^' -f11)

# verify mirror in stable state
if [ "$mirrorCheck" == "true" -a "$mirrortype" == "Failover" -a "$goal" == "running" ]; then
    duration=0
    start=$(date +%s)
    while [ 1 ]; do
        line=$(timeout --signal=SIGKILL $qlistWait iris qlist $iscInstance 2>&1)
        mirrorstatus=$(echo $line | cut -d '^' -f12)
        case $mirrorstatus in
            "Primary" | "Backup" | "Connected" | "Waiting")
                break
                ;;
            *)
                ;;
        esac
        now=$(date +%s)
        duration=$(( $now - $start ))
        if [ "$duration" -gt "$maxWait" -a "$maxWait" -gt 0 ]; then
            echo -e "\nInterSystems IRIS took longer than $maxWait seconds to configure mirroring" |& tee -a $LOG_FILE 1>&2
            exit 1
        fi
        echo -n . |& tee -a $LOG_FILE
        sleep 1
    done
fi

# verify ISCAgent is running
if [ "$iscAgentCheck" == "true" -a "$mirrortype" == "Failover" -a "$goal" == "running" ]; then
    duration=0
    start=$(date +%s)
    while [ 1 ]; do
        now=$(date +%s)
        duration=$(( $now - $start ))

        output=$(timeout --signal=SIGKILL $maxWait iris session $iscInstance -U%SYS '##class(SYS.ICM).ISCAgentCheck()')
        rc=$?
        case "$output" in
            "")
                case $rc in
                    0)
                        # ISCAgent is running and passed connectivity test
                        echo -e "\nWaited $duration seconds for ISCAgent to run" |& tee -a $LOG_FILE
                        break
                        ;;
                    1)
                        # ISCAgent not running or failed connectivity test
                        echo -e "\nISCAgent not running or failed connectivity test. Retrying..." |& tee -a $LOG_FILE
                        ;;
                    2)
                        # Unknown error
                        echo -e "\nISCAgent check returned unknown error. Retrying..." |& tee -a $LOG_FILE
                        ;;
                    124 | 137)
                        # Call timed out
                        ;;
                    *)
                        # Other error
                        ;;
                esac
                ;;
            *"<LICENSE LIMIT EXCEEDED>"*)
                output=$(echo $output | xargs)
                echo -e "\nISCAgent check returned \"$output\". Retrying..." |& tee -a $LOG_FILE
                ;;
            *)
                echo -e "\nError invoking ISCAgent check: "$output |& tee -a $LOG_FILE 1>&2
                exit 1
                ;;
        esac
        if [ "$duration" -gt "$maxWait" -a "$maxWait" -gt 0 ]; then
            echo -e "\nInterSystems IRIS took longer than $maxWait seconds to verify ISCAgent" |& tee -a $LOG_FILE 1>&2
            exit 1
        fi
        echo -n . |& tee -a $LOG_FILE
        sleep 1
    done
fi

# verify shard configuration complete if requested
if [ "$shardCheck" == "true" -a "$goal" == "running" ]; then
    duration=0
    start=$(date +%s)
    while [ 1 ]; do
        now=$(date +%s)
        duration=$(( $now - $start ))

        output=$(timeout --signal=SIGKILL $maxWait iris session $iscInstance -U%SYS '##class(SYS.ICM).ShardingCheck()')
        rc=$?
        case "$output" in
            "")
                case $rc in
                    1)
                        # sharding not requested
                        break
                        ;;
                    2)
                        # sharding requested and complete
                        echo -e "\nWaited $duration seconds for InterSystems IRIS to configure sharding" |& tee -a $LOG_FILE
                        break
                        ;;
                    124 | 137)
                        # call timed out
                        ;;
                    *)
                        # shard configuration underway or other error
                        ;;
                esac
                ;;
            *"<LICENSE LIMIT EXCEEDED>"*)
                output=$(echo $output | xargs)
                echo -e "\nSharding check returned \"$output\". Retrying..." |& tee -a $LOG_FILE
                ;;
            *)
                echo -e "\nError invoking Sharding check: "$output |& tee -a $LOG_FILE 1>&2
                exit 1
                ;;
        esac
        if [ "$duration" -gt "$maxWait" -a "$maxWait" -gt 0 ]; then
            echo -e "\nInterSystems IRIS took longer than $maxWait seconds to configure sharding" |& tee -a $LOG_FILE 1>&2
            exit 1
        fi
        echo -n . |& tee -a $LOG_FILE
        sleep 1
    done
fi

# Wait until auto-start productions are ready
if [ "$productionCheck" == "true" -a "$goal" == "running" ]; then
    duration=0
    start=$(date +%s)
    while [ 1 ]; do
        now=$(date +%s)
        duration=$(( $now - $start ))

        output=$(timeout --signal=SIGKILL $maxWait iris session $iscInstance -U%SYS '##class(SYS.ICM).AutoStartProductionsCheck()')
        rc=$?
        case "$output" in
            "")
                case $rc in
                    0)
                        # All auto-start productions are ready
                        echo -e "\nWaited $duration seconds for InterSystems IRIS to run auto-start productions" |& tee -a $LOG_FILE
                        break
                        ;;
                    2)
                        # Error occured, try again
                        echo -e "\nThere was an error checking the status of auto-start productions. Retrying..." |& tee -a $LOG_FILE
                        ;;
                    3)
                        # Auto-start is not enabled
                        break
                        ;;
                    124 | 137)
                        # Call timed out
                        ;;
                    *)
                        # Some auto-start productions are not ready or other error
                        ;;
                esac
                ;;
            *"<LICENSE LIMIT EXCEEDED>"*)
                output=$(echo $output | xargs)
                echo -e "\Productions check returned \"$output\". Retrying..." |& tee -a $LOG_FILE
                ;;
            *)
                echo -e "\nError invoking Productions check: "$output |& tee -a $LOG_FILE 1>&2
                exit 1
                ;;
        esac
        if [ "$duration" -gt "$maxWait" -a "$maxWait" -gt 0 ]; then
            echo -e "\nInterSystems IRIS took longer than $maxWait seconds to run auto-start productions" |& tee -a $LOG_FILE 1>&2
            exit 1
        fi
        echo -n . |& tee -a $LOG_FILE
        sleep 1
    done
fi

exit 0
