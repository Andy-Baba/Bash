#!/bin/bash
#andisheh.k v1.2 07-Mar-2020

#Includes
my_dir="$(dirname "$0")"
source "$my_dir/utils/lib.logger.sh"

LOG_VERBOS=false
#Today date for generating the report
LOG_FILE=CONSOLE
LOG_LEVEL=INFO
SEPARATOR=,
CONFIG_FILE=$my_dir/enmStatMonitoring.properties

log DEBUG "Entered into $0"
datetime=$(date '+%a %D %T')

reportDate=$(date +%Y-%m-%d)

ROW_FORMAT="<tr><td>%s</td><td align=center>%s</td><td align=center>%.1f</td><td align=center>%.1f</td><td align=center class=%s>%.1f</td><td align=center>%.1f</td><td align=center>%.1f</td><td align=center class=%s>%.1f</td><td align=center class=note>%-d</td><td align=center class=note>%d</td></tr>"

_main(){
    startEpoch=$(date +%s)
    load_config $CONFIG_FILE
    LOG_FILE="$LOG_PATH/$LOG_NAME-$reportDate".log
    log INFO "Start of the script-------------------------"
    log INFO "Verifying the configuration"
    verify_config
    log INFO "Start the analyzing each flow"
    analyze_eachFlowInConfig
    REPORT_FILE=email.html
    log INFO "Generating the report email $REPORT_FILE"
    prepare_report $REPORT_FILE
    send_report $REPORT_FILE
    endEpoch=$(date +%s)
    log INFO "End of the script in $(( endEpoch-startEpoch )) seconds---------------"    
    exit 0
}

#loads the standard bash key/pair configuration file
#Args: configFile 
#out: None
load_config(){
    log DEBUG "Loading the configurations from $1 ..."
    [ ! -f "$1" ] && (log ERROR "File $1 deos not exist! exiting..." || exit 2)
    . "$1"
    log DEBUG "File $configFile loaded sucessfully"
}


verify_config(){
    [ -z "$CC_ADDR" ] && log WARN "CC_ADDR is not defined or empty"
    [ -z "$TO_ADDR" ] && log ERROR "TO_ADDR is required to be set in config. Exit 2" && exit 2
    [ -z "$DURATION" ] && log ERROR "DURATION is required to be set in config. Exit 2" && exit 2
}
#Arguments: None
#Output: an array named 'rows' containing the result of each flow
#Note: If it cannot find anything it will return nothing
analyze_eachFlowInConfig() {
    log DEBUG "Analyzing each flow based on what loaded from config"
    for (( i=1; ; i++ ))
    do
        var="FLOW_$i"
        [ -z "${!var}" ] && break
        log DEBUG "${!var}"
        IFS=$SEPARATOR read name flow threshold statFile <<< "${!var}"
        local tmp="$STAT_PATH/$statFile"
        analyze_stat "$flow" "$tmp*$reportDate* $tmp" $reportDate $threshold "$name"
        flows[$i]=$result
    done
    log DEBUG "Done with code $?"
}

#Analyze the stats based on each flow
#Note: need ROW_FORMAT to be set properly 
#Args: flow, files, time, threshold
#Out: in result; a row containing the information based on ROW_FORMAT
analyze_stat(){
    log DEBUG "with args flow:$1 files:$2 time:$3 threshold:$4 name:$5"
    [ -z "$ROW_FORMAT" ] && (log ERROR "ROW_FORMAT is not set! skippingg..." || return 2)
    result=$(zfgrep -h "$1" $2 | \
    awk -v reportDate="$3" -v threshold="$4" -v name=$5 -v flow="$1" -v rowFormat="$ROW_FORMAT" -F',' \
        'substr($1,1,10) == reportDate { 
            tps[$1]+=$(NF);total[$1]+=$(NF-1);succ[$1]+=$(NF-3);}
        END { 
            minSuccRate=100; 
            for (a in tps) {           
                succRate=succ[a]/total[a]*100;
                lastTPS=tps[a];
                count++; succRateSum+=succRate; tpsSum+=lastTPS;
		if(a > lastTime) lastTime=a;
                if(succRate < minSuccRate) {minSuccRate=succRate; minTime=a}
                if(maxTPS < lastTPS) {maxTime=a; maxTPS=lastTPS}
            }
	    lastTPS=tps[lastTime];
            lastTPM=total[lastTime]/5;
	    succRate=succ[lastTime]/total[lastTime]*100;           
	    aveSuccRate=succRateSum/count;
	    classSuccRate="info";
	    if(succRate < aveSuccRate) classSuccRate="warn";
	    aveTPS=tpsSum/count;
	    classLastTPS="info";
	    if(lastTPS > aveTPS) classLastTPS="warn";
	    if(lastTPS > threshold) classLastTPS="critical"; 

            printf(rowFormat, name, lastTime, minSuccRate, aveSuccRate, classSuccRate, succRate, maxTPS, aveTPS, classLastTPS, lastTPS, threshold, lastTPM);
        }')
	log DEBUG "Done with code $?"	
}

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
    for flow in ${flows[@]}; do
	echo $flow >> $1
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
    EMAIL="$FROM_ADDR" mutt -e 'set  content_type=text/html' $opt -s "$SUBJECT" "$TO_ADDR"  < $1
    [ "$?" != 0 ] && ( log ERROR "Failed to mail $1" || return 2)
    tmp="$LOG_PATH/$1".$(date +"%Y%m%d%H%M%S")
    mv "$1" $tmp
    [ "$?" != 0 ] && log WARN "Could not move $1 to $tmp"     
}

_main
