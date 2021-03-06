#!/bin/bash
#andisheh.k v2.3 06-Jun-2020

#Includes
my_dir="$(dirname "$0")"
source "$my_dir/utils/lib.logger.sh"

LOG_VERBOS=false
LOG_FILE=CONSOLE
LOG_LEVEL=INFO
GLOBAL_ALARM=false
SEPARATOR=,
CONFIG_FILE=$my_dir/enmStatMonitoring.properties

log DEBUG "Entered into $0"
 
TITLES[1]=name
TITLES[2]=lastTime
TITLES[3]=minSuccRate
TITLES[4]=aveSuccRate
TITLES[5]=succRate
TITLES[6]=maxTPS
TITLES[7]=aveTPS
TITLES[8]=lastTPS
TITLES[9]=threshold
TITLES[10]=lastTPM

#Today date for generating the report
datetime=$(date '+%a %D %T')
reportDate=$(date +%Y-%m-%d)
STATE_UPDATE_TIME_MIN=5

_main(){
    startEpoch=$(date +%s)
    load_config $CONFIG_FILE
    LOG_FILE="$LOG_PATH/$LOG_NAME-$reportDate".log
    log INFO "Start of the script-------------------------"
    log INFO "Verifying the configuration"

    declare -A flows
    analyze_config

    declare -A data
    generate_data 

    prepare_rows    

    REPORT_FILE=email.html
    log INFO "Generating the report email $REPORT_FILE"
    prepare_report $REPORT_FILE
    send_report $REPORT_FILE
    endEpoch=$(date +%s)
    log INFO "End of the script in $(( endEpoch-startEpoch )) seconds---------------"    
    exit 0
}

#loads the standard bash key/pair configuration file, it will logs if it failes
#to successfully load the configuratin file.
#Args: configFile 
#Out: None
load_config(){
    log DEBUG "Loading the configurations from $1 ..."
    [ ! -f "$1" ] && (log ERROR "File $1 deos not exist! exiting..." || exit 2)
    . "$1"
    if [ "$?" == 0 ];
    then
        log INFO "File $1 loaded sucessfully"
    else
        log ERROR "There was an issue loading $1, return code is $?,exitting"
        exit 2
    fi
    log DEBUG "Done"
}

#Checks, verifies and extract the flows from the config file
#Dependency: The configuration file should be loaded before calling
#	this function. Associative array 'flows' should be defined before
#	calling this function.
#Args: None
#Out: in flows; Loads the configured flows into 'flows' array
analyze_config(){
    [ -z "$CC_ADDR" ] && log WARN "CC_ADDR is not defined or empty"
    [ -z "$TO_ADDR" ] && log ERROR "TO_ADDR is required to be set in config. Exit 2" && exit 2
    [ -z "$DURATION" ] && log ERROR "DURATION is required to be set in config. Exit 2" && exit 2
    log DEBUG "Reading the flows"
    [ -n "$flows" ] && log ERROR "The associative array 'flows' should be defined, exiting" && exit 2
    for (( i=1; ; i++ ))
    do
        var="FLOW_$i"
        [ -z "${!var}" ] && break
        log DEBUG "${!var}"
          IFS=$SEPARATOR read flows[$i,name] flows[$i,flow] flows[$i,threshold] \
            flows[$i,statFile] flows[$i,family] <<< "${!var}"
        flowsCount=$i
    done
    [ -z "$flowsCount" ] && log WARN "No FLOW was found, check the config file and try again!"
    log DEBUG "Done"
}

#Analyze the stats based on provided argumetns
#Args: flow, file patterns, time
#Out: in result; a commoa separated row containing the information extracted from stats
analyze_stat(){
    log DEBUG "With args flow:$1 files:$2 date:$3"   
    result=$(zfgrep -h "$1" $2 | \
    awk -v duration="$STATE_UPDATE_TIME_MIN" -v reportDate="$3" -v flow="$1" -F "$SEPARATOR" \
        'substr($1,1,10) == reportDate { 
            tps[$1]+=$(NF);total[$1]+=$(NF-1);succ[$1]+=$(NF-3);}
        END { 
            minSuccRate=100; 
            for (a in tps) {
                if(total[a]==0) continue;
                succRate=succ[a]/total[a]*100;
                lastTPS=tps[a];
                count++; succRateSum+=succRate; tpsSum+=lastTPS;
		if(a > lastTime) lastTime=a;
                if(succRate < minSuccRate) {minSuccRate=succRate; minTime=a}
                if(maxTPS < lastTPS) {maxTime=a; maxTPS=lastTPS}
            }
	    lastTPS=tps[lastTime];
            lastTPM=total[lastTime]/duration;
	    succRate=succ[lastTime]/total[lastTime]*100;           
	    aveSuccRate=succRateSum/count;
	    aveTPS=tpsSum/count;
            printf("%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%d", lastTime, minSuccRate, aveSuccRate, succRate, maxTPS, aveTPS, lastTPS, lastTPM); 
        }')
	return $?
}

#It iterates through the 'flows' and extracts the information into 'data'.
#It finds the minSuccRate, aveSuccRate, succRate, maxTPS, aveTPS, lastTPS, 
#lastTPM for each flow in 'flows'. It also checks the type (tag) of each 
#flow and will combine the rows that has same type (tag). It will take just 
#adds "maxTPS, aveTPS, lastTPS, lastTPM" & take the average of " minSuccRate, 
#aveSuccRate, succRate"
#Dependency: The 'flows', 'data' and 'TITLES' associative arrays should be 
#defined before calling this function
#Args: None
#Out: in data
generate_data(){
    [ -n "$flows" ] && log ERROR "The associative array 'flows' should be defined, exiting" && exit 2
    [ -n "$data" ] && log ERROR "The associative array 'data' should be defined, exiting" && exit 2
    declare -A sumRows
    log DEBUG "Start the preparation for $flowsCount flows"
    for (( i=1; i<=flowsCount; i++ ))
    do	
        local tmp="$STAT_PATH/${flows[$i,statFile]}"
 #       ls $tmp > /dev/null 2>&1
 #       [ ! $? -eq 0 ] && log ERROR "Nothing found with pattern: $tmp, skipping..." && continue
        analyze_stat ${flows[$i,flow]} "$tmp*$reportDate* $tmp" $reportDate
	tmpError=$?
	[ $tmpError != 0 ] && log ERROR "Analyze stat failed with $tmpError! Skipping to next..." && continue
        log DEBUG "Processing $result"
        data[$i,name]=${flows[$i,name]}
        data[$i,threshold]=${flows[$i,threshold]}
        IFS=, read data[$i,lastTime] data[$i,minSuccRate] data[$i,aveSuccRate] data[$i,succRate] \
            data[$i,maxTPS] data[$i,aveTPS] data[$i,lastTPS] data[$i,lastTPM] <<< "$result"
        [ $? != 0 ] && log ERROR "Could not extract data from result"

        log DEBUG "Checking for same type of data"
        local type=${flows[$i,family]}
        if  [ -z ${sumRows[$type,count]}  ];then 
            ((typesCount++))
            types[$typesCount]=$type
            log DEBUG "First occurance of flow with type $type"
            sumRows[$type,count]=1
            for a in ${TITLES[@]}; do
                sumRows[$type,$a]=0
            done
            sumRows[$type,name]=${flows[$i,name]}
        else
            ((sumRows[$type,count]++))
            log DEBUG "${sumRows[$type,count]} occurance of type $type"
            sumRows[$type,name]="${sumRows[$type,name]} +${flows[$i,name]}"
        fi
	sumRows[$type,lastTime]=${data[$i,lastTime]}
        for (( j=3; j <=${#TITLES[@]}; j++ )) do 
            local tmp=$(bc<<<"${sumRows[$type,${TITLES[$j]}]}+${data[$i,${TITLES[$j]}]}")
            sumRows[$type,${TITLES[$j]}]=$tmp
        done
        log DEBUG "Going to next result"
    done

    #Calcluate and add the combined rows to data
    dataCount=$flowsCount
    for (( i=1; i<=typesCount; i++ )) do
        local tmp=${sumRows[${types[$i]},count]}
	if [ $tmp -gt 1 ]; then
            ((dataCount++))
            for (( j=1; j<=${#TITLES[@]}; j++ )) do
                local title=${TITLES[$j]}
                if [ $title = minSuccRate ] || [ $title = aveSuccRate ] || [ $title = succRate ]; then
                    local tmp="scale=1;${sumRows[${types[$i]},$title]}/${sumRows[${types[$i]},count]}"
                    data[$dataCount,${TITLES[$j]}]=$(bc<<<"$tmp")
		else
                    data[$dataCount,${TITLES[$j]}]=${sumRows[${types[$i]},${TITLES[$j]}]}
                fi
            done
        fi
    done
    log DEBUG "Done, $dataCount rows is inserted into 'data'"
}

#It converts the information in 'data' into HTML rows
#Dependency: The 'data' and 'TITLES' associative arrays should be 
#defined before calling this function
#Args: None
#Out: in rows
prepare_rows() {
    for (( i=1; i<=dataCount; i++)) do
        local rowName=${data[$i,name]}
        rows[$i]=$(printf "<td>%s</td>" "$rowName")

        for (( j=2; j<${#TITLES[@]}-1; j++ )) do            
            local tmp=${data[$i,${TITLES[$j]}]}
            [ -z "$tmp" ] && log ERROR "${TITLES[$j]} is empty, returning.." && return 2
            rows[$i]=$(printf "%s<td align=center>%s</td>" "${rows[$i]}" "$tmp")
        done

        rows[$i]=$(printf "%s<td align=center class=note><span class=fixed>%'d</span></d>" "${rows[$i]}" "${data[$i,threshold]}")
        local rowTPM=${data[$i,lastTPM]}
        local tmpClass=info
        [ $rowTPM -gt ${data[$i,threshold]} ] && tmpClass=critical && GLOBAL_ALARM=true
        rows[$i]=$(printf "%s<td align=center class=note><span class=%s>%'d</span></td>" "${rows[$i]}" "$tmpClass" "$rowTPM")
        local rowFormat="<tr>%s</t>"
	if [[ $rowName == *" +"* ]]; then
	    rowFormat="<tr class=note>%s</tr>"          
        fi
        rows[$i]=$(printf "$rowFormat" "${rows[$i]}")
    done
    log DEBUG "Done"
}

#It generates the HTML report
#Dependency: The 'rows' and 'TITLES' associative arrays should be 
#defined before calling this function
#Args: None
#Out: in rows
prepare_report(){
    log DEBUG "Writing the report header into $1"
    echo '<html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns:m="http://schemas.microsoft.com/office/2004/12/omml" xmlns="http://www.w3.org/TR/REC-html40">
<head><meta http-equiv=Content-Type content="text/html; charset=windows-1252"><meta name=ProgId content=Word.Document><meta name=Generator content="Microsoft Word 15"><meta name=Originator content="Microsoft Word 15"><link rel=File-List href="Untitled_files/filelist.xml"><link rel=Edit-Time-Data href="Untitled_files/editdata.mso"><link rel=themeData href="Untitled_files/themedata.thmx"><link rel=colorSchemeMapping href="Untitled_files/colorschememapping.xml">
<style>
.heads {font-weight:bold;font-size:14.0pt;}
.info {font-size:12.0pt;color:#00B050;font-weight:bold;}
.fixed {font-size:11.0pt;color:#A5A5A5;font-weight:bold;}
.warn {font-size:12.0pt;color:#FFC000;font-weight:bold;}
.critical {font-size:12.0pt;color:red;font-weight:bold;}
.table {border-collapse:collapse;border:none;mso-border-alt:solid windowtext .5pt;mso-yfti-tbllook:1184;
	mso-padding-alt:0in 5.4pt 0in 5.4pt;}
.tr {mso-yfti-irow:0;mso-yfti-firstrow:yes;}
.td {border:solid windowtext 1.0pt;mso-border-alt:solid windowtext .5pt;padding:0in 5.4pt 0in 5.4pt;}
.td.data {width:100;valign:middle;align:center;background-color:yellow}
.note {background-color:yellow}	
</style><title></title></head>' > $1
    log DEBUG "Wrting the body"    
    echo " 
    <body><div class=WordSection1>
    <p>This is auto generataed on: <span class='info'>$datetime</span></p><p></p>
    <p>Dear NOC,</p><p></p>
    <p>Here is the latest stats of <span class='info'>ITS CS ENM INPUT</span> for past <span class='info'>$DURATION</span> minutes:</p>" >> $1
    log DEBUG "Wrting the result table"
    echo "<table class=MsoTableGrid border=1 cellspacing=0 cellpadding=0>
    <tr class=heads>
    <td width=150 valign=middle align=center rowspan=2>Flow</td>
<td width=150 valign=middle align=center rowspan=2>Time</td>
<td width=300 valign=middle align=center colspan=3>Success Rate</td>
<td width=300 valign=middle align=center colspan=3>Trans. Per Second</td>
<td width=200 valign=middle align=center colspan=2 class=note>Trans. Per Minute</td></tr>
    <tr class=heads style='font-size:12.0pt'>
    <td width=100 valign=middle align=center>Min</td>
    <td width=100 valign=middle align=center>Average</td>
    <td width=100 valign=middle align=center>Last</td>
    <td width=100 valign=middle align=center>Max</td>
    <td width=100 valign=middle align=center>Average</td>
    <td width=100 valign=middle align=center>Last</td>
    <td width=100 valign=middle align=center class=note>Threshold</td>
    <td width=100 valign=middle align=center class=note>Last</td></tr>" >> $1
    for row in ${rows[@]}; do
	echo $row >> $1
    done	
    echo "</table><p>Regards,</p><p>Irancell ITS CS ENM</p></div></body></html>" >> $1
}

#Sends out the report using mutt, and then back up the last sent email
#Args: report_name to be emailed
#Out: None 
send_report(){
    [ ! -f "$1" ] && log ERROR "$1 does not exist" &&  return 2     
    [ ! -z "$CC_ADDR" ] && opt="-c $CC_ADDR"   
    [ -z "$SUBJECT" ] && SUBJECT=NONE
     echo $GLOBAL_ALARM
    [ ! -z "$TO_ALARM" ] && [ "$GLOBAL_ALARM" = true ] && TO_ADDR="$TO_ADDR","$TO_ALARM"
    EMAIL="$FROM_ADDR" mutt -e 'set  content_type=text/html' $opt -s "$SUBJECT" "$TO_ADDR"  < $1
    [ "$?" != 0 ] && ( log ERROR "Failed to mail $1" || return 2)
    log INFO "report is emailed sucessfully"
    tmp="$LOG_PATH/$1".$(date +"%Y%m%d%H%M%S")
    mv "$1" $tmp
    [ "$?" != 0 ] && log WARN "Could not move $1 to $tmp"     
}

_main
