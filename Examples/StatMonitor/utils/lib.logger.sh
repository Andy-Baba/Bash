#andisheh.k v1.0 5-Mar-2020
#Logger Library

##########################Gloabl vars
__DEF__LOG_FILE=crash.log

declare -A __LOG_LEVEL
__LOG_LEVEL[OFF]=0
__LOG_LEVEL[ERROR]=1
__LOG_LEVEL[WARN]=2
__LOG_LEVEL[INFO]=3
__LOG_LEVEL[DEBUG]=4

__FATAL=3
__ERROR=2
__WARN=1
__SUCC=0

LOG_LEVEL=OFF
##########################Internal functions
#if log_level is 'CRASH' it will write in a default log file and EXIT
#Args: log_level, log_mesasge
#Out: logstring
_log_(){
    local time=$(date +"%D,%T")    
    [ "$1" == "CRASH" ] && echo "$time,$1,${FUNCNAME[2]},$2" >> $__DEF__LOG_FILE
    echo "$time,$1,${FUNCNAME[2]},$2"
}

##########################Public functions
log(){
    [ "${__LOG_LEVEL[$1]}" -gt "${__LOG_LEVEL[$LOG_LEVEL]}" ] && return $__WARN
    [ -z $LOG_FILE ] && _log_ CRASH "LOG_FILE paramter is not defined!" && return $__FATAL
    [ "$LOG_FILE" == "CONSOLE" ] && _log_ $1 "$2" && return
    [ $LOG_VERBOS == "true" ] && _log_ $1 "$2" | tee -a $LOG_FILE && return
    _log_ $1 "$2"  >> $LOG_FILE
}
