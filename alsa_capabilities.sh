#!/usr/bin/env bash
# shellcheck disable=SC2191
## ^^ we frequently use arrays for passing arguments to functions.

## This script for linux with bash 4.x displays a list with the audio
## capabilities of each alsa audio output interface and stores them in
## arrays for use in other scripts.  This functionality is exposed by
## the `return_alsa_interface' function which is avaliable after
## sourcing the file. When ran from a shell, it will call that
## function.
##
##  Copyright (C) 2014 Ronald van Engelen <ronalde+github@lacocina.nl>
##  This program is free software: you can redistribute it and/or modify
##  it under the terms of the GNU General Public License as published by
##  the Free Software Foundation, either version 3 of the License, or
##  (at your option) any later version.
##
##  This program is distributed in the hope that it will be useful,
##  but WITHOUT ANY WARRANTY; without even the implied warranty of
##  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##  GNU General Public License for more details.
##
##  You should have received a copy of the GNU General Public License
##  along with this program.  If not, see <http://www.gnu.org/licenses/>.
##
## Source:    https://github.com/ronalde/mpd-configure
## See also:  https://lacocina.nl/detect-alsa-output-capabilities

LANG=C

APP_NAME_AC="alsa-capabilities"
APP_VERSION="0.9.4"
APP_INFO_URL="https://lacocina.nl/detect-alsa-output-capabilities"

## set DEBUG to a non empty value to display internal program flow to
## stderr
DEBUG="${DEBUG:-}"
## set PROFILE to a non empty value to get detailed timing
## information. Normal output is suppressed.
PROFILE="${PROFILE:-}"
## to see how the script behaves with a certain output of aplay -l
## on a particular host, store it's output in a file and supply
## the file path as the value of TESTFILE, eg:
## `TESTFILE=/tmp/somefile ./bash-capabilities
## All hardware and device tests will fail or produce fake outputs
## (hopefully with some grace).
TESTFILE="${TESTFILE:-}"

### generic functions
function die() {
    printf 1>&2 "\nError:\n%s\n\n"  "$@"
    exit 1
}

function debug() {
    lineno="$1"
    message="$2"
    printf 1>&2 "=%.0s"  {1..100}
    printf 1>&2 "\nDEBUG *** %s (%4d): %s\n" \
		"${APP_NAME_AC}" \
		"${lineno}" \
		"${message}"
}

function command_not_found() {
    ## give installation instructions for package $2 when command $1
    ## is not available, optional with non default instructions $3
    ## and exit with error
    command="$1"
    package="$2"
    instructions="${3:-}"
    msg="command \`${command}' (package \`${package}') not found. "
    if [[ -z "${instructions}" ]]; then
	msg+="See 'Requirements' on ${APP_INFO_URL}."
    else
	msg+="${instructions}"
    fi
    die "${msg}"
}

### alsa related functions
function get_aplay_output() {
    ## use aplay to do a basic alsa sanity check using aplay -l, or
    ## optionally using $TESTFILE containing the stored output of
    ## 'aplay -l'.
    ## returns the raw output of aplay or an error.
    res=""
    aplay_msg_nosoundcards_regexp="no[[:space:]]soundcards"
    if [[ "${TESTFILE}x" != "x" ]]; then
	if [[ ! -f "${TESTFILE}" ]]; then
	    # shellcheck disable=SC2059
	    printf 1>&2 "${MSG_APLAY_ERROR_NOSUCHTESTFILE}" \
			"${TESTFILE}"
	    return 1
	else
	    ## get the output from a file for testing purposes
	    # shellcheck disable=SC2059
	    printf  1>&2 "${MSG_APLAY_USINGTESTFILE}\n" \
			 "${TESTFILE}"
	    # shellcheck disable=SC2059
	    res="$(< "${TESTFILE}")" || \
		( printf "${MSG_APLAY_ERROR_OPENINGTESTFILE}" && \
		      return 1 )
	fi
    else
    	## run aplay -l to check for alsa errors or display audio cards
	res="$(${CMD_APLAY} -l 2>&1)" || \
	    (
		# shellcheck disable=SC2059
		printf "${MSG_APLAY_ERROR_GENERAL}\n" "${res}"
		## TODO: react on specific aplay error
		[[ ${DEBUG} ]] && debug "${LINENO}" "\`${CMD_APLAY} -l' returned error: \`${res}'"
		return 1
	    )
	## check for no soundcards
	if [[ "${res}" =~ ${aplay_msg_nosoundcards_regexp} ]]; then
	    printf "%s\n" "${MSG_APLAY_ERROR_NOSOUNDCARDS}"
	    ## TODO: react on specific aplay error
	    [[ ${DEBUG} ]] && debug "${LINENO}" "\`${CMD_APLAY} -l' returned no cards: \`${res}'"
	    return 1
	fi
    fi
    ## return the result to the calling function
    printf "%s" "${res}"
}

function handle_doublebrackets() {
    ## return the name of the alsa card / device, even when they
    ## contain brackets.
    string="$*"
    bracketcounter=0
    for (( i=0; i<${#string}; i++ )); do
	char="${string:$i:1}"
	if [[ "${char}" = "[" ]]; then
	    (( bracketcounter++ ))
	elif [[ "${char}" = "]" ]]; then
	    (( bracketcounter-- ))
	fi
	if (( bracketcounter > 0 )); then
	    ## inside outer brackets
	    if (( bracketcounter < 2 )) && [[ "${char}" == "[" ]]; then
		[[ ${DEBUG} ]] && \
		    debug "${LINENO}" "name with brackets found."
	    else
		# shellcheck disable=SC2059
		printf "${char}"
	    fi
	fi
    done
}

function return_output_human() {
    ## print default output to std_err.
    ## called by fetch_alsa_outputinterfaces.
    printf "%s\n" "${alsa_if_display_title}" 1>&2;
    printf " - %-17s = %-60s\n" \
	   "${MSG_ALSA_DEVNAME}" \
	   "${alsa_dev_label}" 1>&2;
    printf " - %-17s = %-60s\n" \
	   "${MSG_ALSA_IFNAME}" "${alsa_if_label}" 1>&2;
    printf " - %-17s = %-60s\n" \
	   "${MSG_ALSA_UACCLASS}" "${alsa_if_uacclass}" 1>&2;
    printf " - %-17s = %-60s\n" \
	   "${MSG_ALSA_CHARDEV}" "${alsa_if_chardev}" 1>&2;
    if [[ ! -z ${formats_res_err} ]]; then
	## device is locked by an unspecified process
	printf " - %-17s = %-60s\n" \
	       "${MSG_ALSA_ENCODINGFORMATS}" \
	       "${MSG_ERROR_GETTINGFORMATS}"  1>&2;
	printf "   %-17s   %-60s\n" \
	       " " \
	       "${formats_res[@]}"  1>&2;
    else
	formatcounter=0
	if [[ ! -z ${OPT_SAMPLERATES} ]]; then 
	    MSG_ALSA_ENCODINGFORMATS="samplerates (Hz)"
	fi
	printf " - %-17s = " \
	       "${MSG_ALSA_ENCODINGFORMATS}" 1>&2;
	# shellcheck disable=SC2141
	while IFS="\n" read -r line; do
	    (( formatcounter++ ))
	    if (( formatcounter > 1 )); then
		printf "%-23s" " " 1>&2;
	    fi
	    printf "%-60s\n" "${line}" 1>&2;
	done<<<"${alsa_if_formats[@]}"
    fi
    printf " - %-17s = %-60s\n" \
	   "${MSG_ALSA_MONITORFILE}" "${alsa_if_monitorfile}" 1>&2;
    printf " - %-17s = %-60s\n" \
	   "${MSG_ALSA_STREAMFILE}" "${alsa_if_streamfile}" 1>&2;
    printf "\n"
}

function key_val_to_json() {
    ## returns a json "key": "val" pair.
    key="$1"
    val="$2"
    ## check if val is a number
    if printf -v numval "%d" "${val}" 2>/dev/null; then
	## it is
	printf '"%s": %d' \
	       "${key}" "${numval}"
    else
	printf '"%s": "%s"' \
	       "${key}" "${val}"
    fi
    printf "\n"
}

function ret_json_format() {
    ## returns the json formatted encoding format and possibly sample
    ## rates.
    formats_raw="$1"
    declare -a json_formats
    if [[ "${formats_raw}" =~ ':' ]]; then
	## sample rates included
	while read -r line; do
	    split_re="(.*):(.*)"
	    if [[ "${line}" =~ ${split_re} ]]; then
		format=${BASH_REMATCH[1]}
		IFS=" " samplerates=(${BASH_REMATCH[2]})
		printf -v sr_out "\t\t\"%s\",\n" \
		       "${samplerates[@]}"
		sr_out="${sr_out%,*}"
		label_samplerates='"samplerates"'
		output_line="{
           $(key_val_to_json format "${format// /}"),
           ${label_samplerates}: [
${sr_out}
           ]
          }," 
		output_lines+=("${output_line}")
	    fi
	done<<<"${formats_raw}"
	printf -v json_formats "\t%s\n" "${output_lines[@]}"
	## strip the continuation comma from the last element
	json_formats="${json_formats%,*}"
    else
	## no sample rates included
	IFS="," formats_res=(${formats_raw})
	printf -v json_formats '\t\t"%s",\n' \
	       "${formats_res[@]// /}"
	## strip the continuation comma from the last element
	json_formats="${json_formats%,*}"
    fi
    printf "%s" "${json_formats}"
}

function ret_json_card() {
    ## print json formatted output to std_out.
    ## called by fetch_alsa_outputinterfaces.
    #cur_aif_no="$1"
    local str_formats_res="$1"
    last_aif="$2"
    printf -v encoding_formats_val "[\n %s\n\t]" \
	   "$(ret_json_format "${str_formats_res}")"
    ## using to indexed arrays in order to preserve order of fields
    declare -a json_keyvals
    json_fields=(
	id
	hwaddr
	description
	cardnumber
	interfacenumber
	cardname
	interfacename
	chardev
	monitorfile
	streamfile
	usbaudioclass
    )
    json_values=(${cur_aif_no})
    json_values+=(${alsa_if_hwaddress})
    #a_json_keyvals[description]=
    json_values+=("${alsa_if_title_label}")
    #a_json_keyvals[cardnumber]=
    json_values+=(${alsa_dev_nr})
    #a_json_keyvals[interfacenumber]=
    json_values+=(${alsa_if_nr})
    #a_json_keyvals[cardname]=
    json_values+=("${alsa_dev_label}")
    #a_json_keyvals[interfacename]=
    json_values+=("${alsa_if_label}")
    #a_json_keyvals[chardev]=
    json_values+=(${alsa_if_chardev})
    #a_json_keyvals[monitorfile]=
    json_values+=(${alsa_if_monitorfile})
    #a_json_keyvals[streamfile]=
    json_values+=(${alsa_if_streamfile})
    #a_json_keyvals[usbaudioclass]=
    json_values+=("${alsa_if_uacclass}")

    for json_fieldno in "${!json_fields[@]}"; do
	json_keyvals+=("$(key_val_to_json \
"${json_fields[${json_fieldno}]}" "${json_values[${json_fieldno}]}")")
    done
    printf -v str_json_keyvals "\t%s,\n" "${json_keyvals[@]}"
    # shellcheck disable=SC1078,SC1079,SC2027
    aif_json="""\
     {
${str_json_keyvals%,*}
        \"encodingformats\": "${encoding_formats_val}" 
     }\
"""
    printf "%s" "${aif_json}"
    if [[ "${last_aif}x" == "x" ]]; then
	printf ","
    fi
    printf "\n"
}

function return_output_json() {
    ## print json formatted output to std_out.
    ## called by fetch_alsa_outputinterfaces.
    json_cards="$1"
    json='{
 "alsa_outputdevices": [ 
    %s
  ]
}'
    # shellcheck disable=SC2059
    printf "${json}\n" "${json_cards%,*}"
}





function fetch_alsa_outputinterfaces() {
    ## parses each output interface returned by `get_aplay_output'
    ## after filtering (when the appropriate commandline options are
    ## given), stores its capabilities in the appropriate global
    ## indexed arrays and displays them.
    json_output=
    msg=()
    aplay_lines=()
    integer_regexp='^[0-9]+$'
    aplay_card_regexp="^card[[:space:]][0-9]+:"
    ## exit on error
    #aplay_output="$
    ## reset the counter for interfaces without filtering
    NR_AIFS_BEFOREFILTERING=0
    ## modify the filter for aplay -l when OPT_HWFILTER is set
    if [[ ! -z "${OPT_HWFILTER}" ]]; then
	# the portion without `hw:', eg 0,1
	alsa_filtered_hwaddr="${OPT_HWFILTER#hw:*}"
	alsa_filtered_cardnr="${alsa_filtered_hwaddr%%,*}"
	alsa_filtered_devicenr="${alsa_filtered_hwaddr##*,}"
	if [[ ! ${alsa_filtered_cardnr} =~ ${integer_regexp} ]] || \
	       [[ ! ${alsa_filtered_devicenr} =~ ${integer_regexp} ]]; then
	    msg+=("Invalid OPT_HWFILTER (\`${OPT_HWFILTER}') specified.")
	    msg+=("Should be \`hw:x,y' were x and y are both integers.")
	    printf -v msg_str "%s\n" "${msg[@]}"
	    die "${msg_str}"
	fi
	aplay_card_regexp="^card[[:space:]]${alsa_filtered_cardnr}:[[:space:]].*"
	aplay_device_regexp="[[:space:]]device[[:space:]]${alsa_filtered_devicenr}:"
	aplay_card_device_regexp="${aplay_card_regexp}${aplay_device_regexp}"
    else
	aplay_card_device_regexp="${aplay_card_regexp}"
    fi
    ## iterate each line of aplay output
    while read -r line ; do
	## filter for `^card' and then for `OPT_CUSTOMFILTER' to get matching
	## lines from aplay and store them in an array
	if [[ "${line}" =~ ${aplay_card_device_regexp} ]]; then
	    [[ ${DEBUG} ]] && \
		( msg_debug="aplay -l output line: \`${line}'. with OPT_CUSTOMFILTER: ${OPT_CUSTOMFILTER}"
		debug "${LINENO}" "${msg_debug}")
	    ## raise the counter for interfaces without filtering
	    ((NR_AIFS_BEFOREFILTERING++))
	    if [[ "${OPT_CUSTOMFILTER}x" != "x" ]]; then
		## check if line matches `OPT_CUSTOMFILTER'
		if [[ "${line}" =~ ${OPT_CUSTOMFILTER} ]]; then
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "match: ${line}"
		    ## store the line in an array
		    aplay_lines+=("${line}")
		else
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "no match with filter ${OPT_CUSTOMFILTER}: ${line}"
		fi
	    else
		## store the line in an array
		aplay_lines+=("${line}")
	    fi
	fi
    done< <(get_aplay_output "${aplay_card_regexp}") ||  \
	die "get_aplay_output '${aplay_card_regexp}' returned an error."
#< "${aplay_output}"
    ## check whether soundcards were found
    NR_AIFS_AFTERFILTERING=${#aplay_lines[@]}
    if (( NR_AIFS_AFTERFILTERING < 1 )); then
	die "${#aplay_lines[@]} soundcards found"
    fi

    ## loop through each item in the array
    cur_aif_no=0
    for line in "${aplay_lines[@]}"; do
	((cur_aif_no++))
	## set if type to default (ie analog)
	alsa_if_type="ao"
	## construct bash regexp for sound device
	## based on aplay.c:
	## printf(_("card %i: %s [%s], device %i: %s [%s]\n"),
	## 1 card,
	## 2 snd_ctl_card_info_get_id(info),
	## 3 snd_ctl_card_info_get_name(info),
	## 4 dev,
	## 5 snd_pcm_info_get_id(pcminfo),
	## 6 snd_pcm_info_get_name(pcminfo));
	##
	## portion (ie before `,')
	alsa_dev_regexp="card[[:space:]]([0-9]+):[[:space:]](.*)[[:space:]]\[(.*)\]"
	## same for interface portion
	alsa_if_regexp=",[[:space:]]device[[:space:]]([0-9]+):[[:space:]](.*)[[:space:]]\[(.*)\]"
	alsa_dev_if_regexp="^${alsa_dev_regexp}${alsa_if_regexp}$"
	## unset / empty out all variables
	alsa_dev_nr=""
	alsa_dev_name=""
	alsa_dev_label=""
	alsa_if_nr=""
	alsa_if_name=""
	alsa_if_label=""
	## start matching and collect errors in array
	errors=()
	## see if the name contains square brackets, ie it ends with `]]'
	name=""
	alsacard=""
	separator_start="*##"
	separator_end="##*"
	name_re="card[[:space:]][0-9]+:[[:space:]](.*)\[.*\[.*\]\].*"
	brackets_re="card[[:space:]]([0-9]+):(.*\])\],[[:space:]](device[[:space:]][0-9]+:.*\])"
	if [[ "${line}" =~ ${brackets_re} ]]; then
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "#####: line with brackets \`${line}'"
	    if [[ "${line}" =~ ${name_re} ]]; then
		name="${BASH_REMATCH[1]}"
		[[ ${DEBUG} ]] && \
		    debug "${LINENO}" "#####: name \`${name}'"
	    fi
	fi
	if [[ ! -z "${name}" ]]; then
	    if [[ "${line}" =~ ${brackets_re} ]]; then
		## construct string without brackets
		alsacard="$(handle_doublebrackets "${BASH_REMATCH[2]}")"
		[[ ${DEBUG} ]] && \
		    debug "${LINENO}" "#####: alsacard: \`${alsacard}'"
		## replace `name [something]' with `name *##something##*'
		alsacard="${alsacard//\[/${separator_start}}"
		alsacard="${alsacard//\]/${separator_end}}"
		line="card ${BASH_REMATCH[1]}: ${name}[${alsacard}], ${BASH_REMATCH[3]}"
		[[ ${DEBUG} ]] && \
		    debug "${LINENO}" "#####: replace line with \`${line}'"
	    fi
	fi
	## match the current line with the regexp
	if [[ "${line}" =~ ${alsa_dev_if_regexp} ]]; then
	    [[ ! -z "${BASH_REMATCH[1]}" ]] && \
		alsa_dev_nr="${BASH_REMATCH[1]}" || \
		    errors+=("could not fetch device number")
	    if [[ ! -z "${BASH_REMATCH[2]}" ]]; then
		alsa_dev_name="${BASH_REMATCH[2]}"
		## reconstruct original name if it contained square brackets
		alsa_dev_name="${alsa_dev_name//${separator_start}/\[}"
		alsa_dev_name="${alsa_dev_name//${separator_end}/\]}"
	    else
		errors+=("could not fetch device name")
	    fi
	    [[ ! -z "${BASH_REMATCH[3]}" ]] && \
		alsa_dev_label="${BASH_REMATCH[3]}" || \
		    errors+=("could not fetch device label")
	    [[ ! -z "${BASH_REMATCH[4]}" ]] && \
		alsa_if_nr="${BASH_REMATCH[4]}" || \
		    errors+=("could not fetch interface number")
	    [[ ! -z "${BASH_REMATCH[5]}" ]] && \
		alsa_if_name="${BASH_REMATCH[5]}" || \
		    errors+=("could not fetch interface name")
	    [[ ! -z "${BASH_REMATCH[6]}" ]] && \
		alsa_if_label="${BASH_REMATCH[6]}" || \
		    errors+=("could not fetch interface label")
	    ## empty numbers and names of devices and interfaces are fatal
	    if (( ${#errors[@]} > 0 )); then
		printf -v msg_err "%s\n" "${errors[@]}"
		die "${msg_err}"
		break
	    fi
	    declare -a alsa_if_formats=()
	    alsa_if_hwaddress="hw:${alsa_dev_nr},${alsa_if_nr}"
	    ## construct the path to the character device for the
	    ## interface (ie `/dev/snd/xxx')
	    alsa_if_chardev="/dev/snd/pcmC${alsa_dev_nr}D${alsa_if_nr}p"
	    ## construct the path to the hwparams file
	    alsa_if_hwparamsfile="/proc/asound/card${alsa_dev_nr}/pcm${alsa_if_nr}p/sub0/hw_params"
	    ## before determining whether this is a usb device, assume
	    ## the monitor file is the hwparams file
	    alsa_if_monitorfile="${alsa_if_hwparamsfile}"
	    ## assume stream file for the interface (ie
	    ## `/proc/asound/cardX/streamY') to determine whether
	    ## the interface is a uac device, and if so, which class it is
	    alsa_if_streamfile="/proc/asound/card${alsa_dev_nr}/stream${alsa_if_nr}"
	    ## assume no uac device
	    alsa_if_uacclass="${MSG_PROP_NOTAPPLICABLE}"

	    if [[ ! -z ${TESTFILE} ]]; then
		## device is not real
		alsa_if_formats+=("(${MSG_ERROR_CHARDEV_NOFORMATS})")
		alsa_if_uacclass_nr="?"
	    else
		## check if the hwparams file exists
		if [[ ! -f "${alsa_if_hwparamsfile}" ]]; then
		    alsa_if_hwparamsfile="${alsa_if_hwparamsfile} (error: not accessible)"
		fi
		## check if the chardev exists
		if [[ ! -c "${alsa_if_chardev}" ]]; then
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "alsa_if_chardev \`${alsa_if_chardev}' is not a chardev."
		    alsa_if_chardev="${alsa_if_chardev} (${MSG_ERROR_NOT_CHARDEV})"
		else
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "alsa_if_chardev \`${alsa_if_chardev}' is a valid chardev."
		fi
		## check whether the monitor file exists; it always should
		if [[ ! -f ${alsa_if_monitorfile} ]]; then
		    msg_err="${alsa_if_monitorfile} ${MSG_ERROR_NOFILE} (${MSG_ERROR_UNEXPECTED})"
		    alsa_if_monitorfile="${msg_err}"
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "${MSG_ERROR_UNEXPECTED}: alsa_if_monitorfile \
\`${alsa_if_monitorfile}' ${MSG_ERROR_NOFILE}"
		fi
		## check whether the streamfile exists; it only should
		## exist in the case of a uac interface
		if [[ ! -f "${alsa_if_streamfile}" ]]; then
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "alsa_if_streamfile \`${alsa_if_streamfile}' \
${MSG_ERROR_NOFILE}"
		    ## no uac interface
		    alsa_if_streamfile="${MSG_PROP_NOTAPPLICABLE}"
		else
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "using alsa_if_streamfile \`${alsa_if_streamfile}'."
		    ## set interface to usb out
		    alsa_if_type="uo"
		    ## uac devices will use the stream file instead of
		    ## hwparams file to monitor
		    ## alsa_if_monitorfile="${alsa_if_streamfile}"
		    ## get the type of uac endpoint
		    alsa_if_uac_ep="$(return_alsa_uac_ep "${alsa_if_streamfile}")"
		    # shellcheck disable=SC2181
		    if [[ $? -ne 0 ]]; then
			[[ ${DEBUG} ]] && \
			    debug "${LINENO}" "could not determine alsa_if_uac_ep."
			alsa_if_uacclass_nr="?"
		    else
			[[ ${DEBUG} ]] && \
			    debug "${LINENO}" "alsa_if_uac_ep set to \`${alsa_if_uac_ep}'."
			## lookup the uac class in the array for this type of endpoint (EP)
			## (for readability)
			alsa_if_uacclass="${UO_EP_LABELS[${alsa_if_uac_ep}]}"
			## the uac class number (0, 1, 2 or 3) according to ./sound/usb/card.h
			alsa_if_uacclass_nr="${alsa_if_uacclass% - *}"
			classnr_regexp='^[0-3]+$'
			if [[ ! ${alsa_if_uacclass_nr} =~ ${classnr_regexp} ]]; then
			    [[ ${DEBUG} ]] && \
				debug "${LINENO}" "invalid uac class number \`${alsa_if_uacclass_nr}'. \
${MSG_ERROR_UNEXPECTED}"
			    alsa_if_uacclass_nr="?"
			fi
		    fi

		fi
	    fi
	fi
	## for non-uac interfaces: check whether it is some other
	## digital interface
	if [[ ! "${alsa_if_type}" = "uo" ]]; then
	    for filter in "${DO_INTERFACE_FILTER[@]}"; do
		## `,,' downcases the string, while `*var*' does a
		## wildcard match
		if [[ "${alsa_if_name,,}" == *"${filter}"* ]]; then
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "match = ${alsa_if_name,,}: ${filter}"
		    ## set ao type to d(igital)o(out)
		    alsa_if_type="do"
		    ## exit this for loop
		    break
		fi
	    done
	fi
	## see if the interface type matches the user specified
	## filters and if so construct titles and store a pair of
	## hardware address and monitoring file in the proper array
	match=
	case "${alsa_if_type}" in
	    "ao")
		## only if neither `OPT_LIMIT_DO' and `OPT_LIMIT_UO' are set
		[[ ! -z ${OPT_LIMIT_DO} || ! -z ${OPT_LIMIT_UO} ]] && \
		    continue || match="true"
		;;
	    "do")
		## only if neither `OPT_LIMIT_AO' and `OPT_LIMIT_UO' are set
		[[ ! -z ${OPT_LIMIT_AO} || ! -z ${OPT_LIMIT_UO} ]] && \
		    continue || match="true"
		;;
	    "uo")
		## only if `OPT_LIMIT_AO' is not set
		[[ ! -z ${OPT_LIMIT_AO} ]] && \
		    continue || match="true"
	esac
	if [[ ! -z ${match} ]]; then
	    ## put each encoding format and possibily the sample rates
	    ## in an array
	    alsa_if_formats=()
	    formats_res_err=
	    str_formats_res="$(return_alsa_formats \
"${alsa_dev_nr}" \
"${alsa_if_nr}" \
"${alsa_if_type}" \
"${alsa_if_streamfile}" \
"${alsa_if_chardev}")"
	    # shellcheck disable=SC2181
	    if [[ $? -ne 0 ]]; then
		formats_res_err=1
	    fi
	    alsa_if_formats+=("${str_formats_res}")
	    alsa_if_title_label="${ALSA_IF_LABELS[${alsa_if_type}]}"
	    ## reconstruct the label if it contained square brackets
	    if [[ "${alsa_dev_label}" =~ .*${separator_start}.* ]]; then
		alsa_dev_label="${alsa_dev_label//\*##/\[}"
		alsa_dev_label="${alsa_dev_label//##\*/\]}"
	    fi
	    ## construct the display title
	    printf -v alsa_if_display_title \
		   " %s) %s \`%s'" \
		   "${cur_aif_no}" \
		   "${alsa_if_title_label}" \
		   "${alsa_if_hwaddress}"
	    ## store the details of the current interface in global arrays
	    ALSA_AIF_HWADDRESSES+=("${alsa_if_hwaddress}")
	    ALSA_AIF_MONITORFILES+=("${alsa_if_monitorfile}")
	    ALSA_AIF_DISPLAYTITLES+=("${alsa_if_display_title}")
	    ALSA_AIF_DEVLABELS+=("${alsa_dev_label}")
	    ALSA_AIF_LABELS+=("${alsa_if_label}")
	    ALSA_AIF_UACCLASSES+=("${alsa_if_uacclass}")
	    ALSA_AIF_FORMATS="${alsa_if_formats[*]}"
	    ALSA_AIF_CHARDEVS+=("${alsa_if_chardev}")
	fi
	if [[ -z "${OPT_QUIET}" ]] && [[ "${OPT_JSON}x" == "x" ]]; then
	    ## print the list to std_err
	    res_human="$(return_output_human)" || exit 1
	    printf 1>&2 "%s\n" "${res_human}"
	fi
	if [[ "${OPT_JSON}x" != "x" ]]; then
	    if [[ ${cur_aif_no} -lt ${#aplay_lines[@]} ]]; then 
		printf -v json_output "%s%s\n" \
		       "${json_output}" \
		       "$(ret_json_card "${str_formats_res}" "")"
	    fi
	fi
    done
    if [[ "${OPT_JSON}x" != "x" ]]; then
	res_json="$(return_output_json "${json_output}")" || exit 1
	printf "%s\n" "${res_json}"
    fi
}

function get_locking_process() {
    ## return a string describing the command and id of the
    ## process locking the audio interface with card nr $1 and dev nr
    ## $2 based on its status file in /proc/asound.
    ## returns a comma separated string containing the locking cmd and
    ## pid, or an error when the interface is not locked (ie
    ## 'closed').
    alsa_card_nr="$1"
    alsa_if_nr="$2"
    proc_statusfile="/proc/asound/card${alsa_card_nr}/pcm${alsa_if_nr}p/sub0/status"
    owner_pid=
    owner_stat=
    owner_cmd=
    parent_pid=
    parent_cmd=
    locking_cmd=
    locking_pid=
    ## specific for mpd: each alsa output plugin results in a locking
    ## process indicated by `owner_pid` in
    ## /proc/asound/cardX/pcmYp/sub0/status: `owner_pid   : 28022'
    ## this is a child process of the mpd parent process (`28017'):
    ##mpd(28017,mpd)-+-{decoder:flac}(28021)
    ##               |-{io}(28019)
    ##               |-{output:Peachtre}(28022) <<< owner_pid / child
    ##               `-{player}(28020)
    owner_pid_re="owner_pid[[:space:]]+:[[:space:]]+([0-9]+)"
    [[ ${DEBUG} ]] && \
	debug "${LINENO}" "examining status file ${proc_statusfile}." 
    while read -r line; do
	if [[ "${line}" =~ ${owner_pid_re} ]]; then
	    owner_pid="${BASH_REMATCH[1]}"
	    break
	elif [[ "${line}" == "closed" ]]; then
	    return 1
	fi
    done<"${proc_statusfile}"
    [[ ${DEBUG} ]] && \
	debug "${LINENO}" "done examining status file ${proc_statusfile}." 
    if [[ -z ${owner_pid} ]]; then
	## device is unused
	[[ ${DEBUG} ]] && \
	    debug "${LINENO}" "${FUNCNAME[0]} called, but no owner_pid found in \`${proc_statusfile}'."
	return 1
    else
	[[ ${DEBUG} ]] && \
	    debug "${LINENO}" "found owner pid in status file \`${proc_statusfile}': \`${owner_pid}'."
    fi
    ## check if owner_pid is a child
    ## construct regexp for getting the ppid from /proc
    ## eg: /proc/837/stat:
    ## 837 (output:Pink Fau) S 1 406 406 0 -1 ...
    ## ^^^                       ^^^
    ## +++-> owner_pid           +++-> parent_pid
    parent_pid_re="(${owner_pid})[[:space:]]\(.*\)[[:space:]][A-Z][[:space:]][0-9]+[[:space:]]([0-9]+)"
    # shellcheck disable=SC2162
    read owner_stat < "/proc/${owner_pid}/stat"
    [[ ${DEBUG} ]] && \
	debug "${LINENO}" "owner_stat: \`${owner_stat}'"
    if [[ "${owner_stat}" =~ ${parent_pid_re} ]]; then
	parent_pid="${BASH_REMATCH[2]}"
	if [[ "x${parent_pid}" == "x${owner_pid}" ]]; then
	    ## device is locked by the process with id owner_pid, look up command
	    ## eg: /proc/837/cmdline: /usr/bin/mpd --no-daemon /var/lib/mpd/mpd.conf
	    # shellcheck disable=SC2162
	    read owner_cmd < "/proc/${owner_pid}/cmdline"
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "cmd \`${owner_cmd}' with id \`${owner_pid}' has no parent."
	    locking_pid="${owner_pid}"
	    locking_cmd="${owner_cmd}"
	else
	    ## device is locked by the parent of the process with owner_pid
	    # shellcheck disable=SC2162	    
	    read owner_cmd < "/proc/${owner_pid}/cmdline"
	    # shellcheck disable=SC2162	    
	    read parent_cmd < "/proc/${parent_pid}/cmdline"
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "cmd \`${owner_cmd}' with id \`${owner_pid}' \
has parent cmd \`${parent_cmd}' with id \`${parent_pid}'."
	    locking_pid="${parent_pid}"
	    locking_cmd="${parent_cmd}"
	fi
	## return comma separated list (pid,cmd) to calling function
	locking_cmd="$(while read -r -d $'\0' line; do \
			     printf "%s " "${line}"; \
			     done< "/proc/${locking_pid}/cmdline")"
	printf "%s,%s" "${locking_pid}" "${locking_cmd%% }"
    else
	## should not happen; TODO: handle
	parent_pid=
    fi 
}

function ret_highest_alsa_samplerate() {
    ## check the highest supported rate of type $3 for format $2 on
    ## interface $1
    ## returns the highest supported rate.
    alsa_if_hwaddress="$1"
    encoding_format="$2"
    type="$3"
    if [[ "${type}" == "audio" ]]; then
	rates=(${SAMPLERATES_AUDIO[@]})
    else
	rates=(${SAMPLERATES_VIDEO[@]})
    fi
    for rate in "${rates[@]}"; do
	res="$(check_samplerate "${alsa_if_hwaddress}" "${encoding_format}" "${rate}")"
	# shellcheck disable=SC2181	
	if [[ $? -ne 0 ]]; then
	    ## too high; try next one
	    continue
	else
	    ## match; return it
	    printf "%s" "${rate}"
	    break
	fi
    done
}

function ret_supported_alsa_samplerates() {
    ## use aplay to get supported sample rates for playback for
    ## specified non-uac interface ($1) and encoding format ($2).
    ## returns a space separated list of valid rates.
    alsa_if_hwaddress="$1"
    encoding_format="$2"
    declare -a rates
    [[ ${DEBUG} ]] && \
	debug "${LINENO}" "getting sample rates for device \`${alsa_if_hwaddress}' \
using encoding_format \`${encoding_format}'."    
    ## check all audio/video rates from high to low; break when rate is
    ## supported while adding all the lower frequencies
    highest_audiorate="$(ret_highest_alsa_samplerate \
"${alsa_if_hwaddress}" "${encoding_format}" "audio")"
    highest_videorate="$(ret_highest_alsa_samplerate \
"${alsa_if_hwaddress}" "${encoding_format}" "video")"
    for rate in "${SAMPLERATES_AUDIO[@]}"; do
	if [[ ${rate} -le ${highest_audiorate} ]]; then
	    ## supported; assume all lower rates are supported too
	    rates+=("${rate}")
	fi		    
    done
    for rate in "${SAMPLERATES_VIDEO[@]}"; do
	if [[ ${rate} -le ${highest_videorate} ]]; then
	    ## supported; assume all lower rates are supported too
	    rates+=("${rate}")
	fi		    
    done
    ## sort and retrun trhe newline separated sample rates
    sort -u -n <(printf "%s\n" "${rates[@]}")
}

function check_samplerate() {
    ## use aplay to check if the specified alsa interface ($1)
    ## supports encoding format $2 and sample rate $3
    ## returns a string with the supported sample rate or nothing
    alsa_if_hwaddress="$1"
    format="$2"
    samplerate="$3"
    declare -a aplay_args_early
    aplay_args_early+=(--device="${alsa_if_hwaddress}")
    aplay_args_early+=(--format="${format}")
    aplay_args_early+=(--channels="2")
    aplay_args_early+=(--nonblock)
    declare -a aplay_args_late
    ## set up regular expressions to match aplay's output errors
    ## unused
    # shellcheck disable=SC2034
    rate_notaccurate_re=".*Warning:.*not[[:space:]]accurate[[:space:]]\(requested[[:space:]]=[[:space:]]([0-9]+)Hz,[[:space:]]got[[:space:]]=[[:space:]]([0-9]+)Hz\).*"
    # shellcheck disable=SC2034    
    badspeed_re=".*bad[[:space:]]speed[[:space:]]value.*"
    # shellcheck disable=SC2034    
    sampleformat_nonavailable_re=".*Sample[[:space:]]format[[:space:]]non[[:space:]]available.*"
    # shellcheck disable=SC2034    
    wrongformat_re=".*wrong[[:space:]]extended[[:space:]]format.*"
    ## used
    default_re=".*Playing[[:space:]]raw[[:space:]]data.*"
    [[ ${DEBUG} ]] && \
	debug "${LINENO}" "testing rate ${samplerate}"
    unset aplay_args_late
    ## set fixed sample rate
    aplay_args_late+=(--rate="${samplerate}")
    ## generate aplay error using random noise to check whether sample
    ## rate is supported for this interface and format
    # shellcheck disable=SC2145
    printf -v aplay_args "%s " "${aplay_args_early[@]} ${aplay_args_late[@]}"
    read -r firstline<<<"$(return_reversed_aplay_error "${aplay_args}")" || return 1
    if [[ "${firstline}" =~ ${default_re} ]]; then
	[[ ${DEBUG} ]] && \
	    debug "${LINENO}" "success"
	printf "%s" "${samplerate}"
    else
	return 1
    fi
}

function return_reversed_aplay_error() {
    ## force aplay to output error message containing supported
    ## encoding formats, by playing PSEUDO_AUDIO in a non-existing
    ## format.
    ## returns the output of aplay while reversing its return code
    aplay_args="$1"
    cmd_aplay="${CMD_APLAY} ${aplay_args}"
    LANG=C ${cmd_aplay} 2>&1 <<< "${PSEUDO_SILENT_AUDIO}" || \
	( [[ ${DEBUG} ]] && \
	      debug "${LINENO}" "\`${cmd_aplay}' returned error (which is good)."
	  return 0 ) && \
	    ( [[ ${DEBUG} ]] && \
		  debug "${LINENO}" "\`${cmd_aplay}' returned error (which is not good)."
	      return 1 )
}

function return_nonuac_formats() {
    ## use aplay to determine supported formats of non-uac interface (hw:$1,$2)
    alsa_dev_nr="$1"
    alsa_if_nr="$2"
    aplay_args=(--device=hw:${alsa_dev_nr},${alsa_if_nr})
    aplay_args+=(--channels=2)
    aplay_args+=(--format=MPEG)
    aplay_args+=(--nonblock)
    printf -v str_args "%s " "${aplay_args[@]}"
    return_reversed_aplay_error "${str_args}" || \
	return 1
}

function return_uac_formats_rates() {
    ## get encodings formats with samplerates for uac type interface
    ## using its streamfile $1 (which saves calls to applay).
    ## returns newline separated list (FORMAT:RATE,RATE,...).
    alsa_if_streamfile="$1"
    interface_re="^[[:space:]]*Interface[[:space:]]([0-9])"
    format_re="^[[:space:]]*Format:[[:space:]](.*)"
    rates_re="^[[:space:]]*Rates:[[:space:]](.*)"
    capture_re="^Capture:"
    inside_interface=
    format_found=
    declare -A uac_formats_rates
    ## iterate lines in the streamfile
    while read -r line; do
	if [[ "${line}" =~ ${capture_re} ]]; then
	    ## end of playback interfaces
	    break
	else
	    ## we're not dealing with a capture interface
	    if [[ "${line}" =~ ${interface_re} ]]; then
		## new interface found
		inside_interface=true
		## reset (previous) format_found
		format_found=
		## continue with next line
	    else
		## continuation of interface 
		if [[ "${inside_interface}x" != "x" ]]; then
		    ## parse lines below `Interface:`
		    if [[ "${format_found}x" == "x" ]]; then
			## check for new `Format:`
			if [[ "${line}" =~ ${format_re} ]]; then
			    ## new format found
			    format_found="${BASH_REMATCH[1]}"
			    uac_formats_rates[${format_found}]=""
			    [[ ${DEBUG} ]] && \
				debug "${LINENO}" "format found: \`${format_found}'"
			    ## next: sample rates or new interface
			fi
		    else
			## parse lines below `Format:`
			if [[ "${line}" =~ ${rates_re} ]]; then
			    ## sample rates for interface/format found;
			    ## return and reset both
			    uac_formats_rates[${format_found}]="${BASH_REMATCH[1]}"
			    [[ ${DEBUG} ]] && \
				debug "${LINENO}" "(format=${format_found}) \
rates=${BASH_REMATCH[1]}"
			    format_found=
			    inside_interface=
			    continue
			fi
		    fi
		fi
	    fi
	fi
    done<"${alsa_if_streamfile}"
    for format in "${!uac_formats_rates[@]}"; do
	printf "%s:%s\n" \
	       "${format}" "${uac_formats_rates[${format}]// /}"
    done
}

function return_alsa_formats() {
    ## fetch and return a comma separated string of playback formats
    ## for the interface specified in $1, of type $2. For non-uac
    ## interfaces: feed dummy input to aplay (--format=MPEG). For uac
    ## types: filter it directly from its stream file $3.
    alsa_dev_nr="$1"
    alsa_if_nr="$2"
    alsa_if_type="$3"
    alsa_if_streamfile="$4"
    alsa_if_chardev="$5"
    format="${format:-}"
    rawformat="${rawformat:-}"
    parent_pid=
    parent_cmd=
    declare -A uac_formats
    if [[ "${alsa_if_type}" = "uo" ]]; then
	## uac type; use streamfile to get encoding formats and/or
	## samplerates (in the form of 'FORMAT: RATE RATE ...').
	while read -r line; do
	    key="${line%:*}"
	    value="${line//${key}:/}"
	    uac_formats["${key}"]="${value}"
	done< <(return_uac_formats_rates "${alsa_if_streamfile}")
	## return the formatted line(s)
	if [[ "${OPT_SAMPLERATES}x" == "x" ]]; then
	    ## print comma separated list of formats
	    # shellcheck disable=SC2068
	    printf -v str_formats "%s, " "${!uac_formats[@]}"
	    printf "%-20s" "${str_formats%*, }"
	else	    
	    ## for each format, print "FORMAT1:rate1,rate2,..."
	    # shellcheck disable=SC2068
	    for key in ${!uac_formats[@]}; do
	 	printf "%s:%s\n" "${key}" "${uac_formats[${key}]}"
	    done
	fi
    else
	## non-uac type: if interface is not locked, use aplay to
	## determine formats
	## because of invalid file format, aplay is forced to return
	## supported formats (=200 times faster than --dump-hw-params)
	declare -a rawformats
	format_re="^-[[:space:]]+([[:alnum:]_]*)$"
	res="$(get_locking_process "${alsa_dev_nr}" "${alsa_if_nr}")"
	# shellcheck disable=SC2181
	if [[ $? -ne 0 ]]; then
	    ## device is not locked, iterate aplay output
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "device is not locked; will iterate aplay_out"
	    while read -r line; do
		if [[ "${line}" =~ ${format_re} ]]; then
		    rawformats+=(${BASH_REMATCH[1]})
		fi
	    done< <(return_nonuac_formats "${alsa_dev_nr}" "${alsa_if_nr}") || return 1
	    ## formats (and minimum/maximum sample rates) gathered, check if
	    ## all sample rates should be checked
	    [[ ${DEBUG} ]] && debug "${LINENO}" "$(declare -p rawformats)"
	    if [[ "${OPT_SAMPLERATES}x" == "x" ]]; then
		## just return the comma separated format(s)
		printf -v str_formats "%s, " "${rawformats[@]}"
		printf "%-20s" "${str_formats%*, }"
	    else
		## check all sample rates for each format.  warning:
		## slowness ahead for non-uac interfaces, because of
		## an aplay call for each unsupported sample rate + 1
		## and each format
		for rawformat in "${rawformats[@]}"; do
		    sorted_rates=""
		    while read -r line; do
			sorted_rates+="${line},"
			#printf -v str_rates "%s " "${line}"
		    done< <(ret_supported_alsa_samplerates \
				"${alsa_if_hwaddress}" "${rawformat}")
		    ## return each format newline separated with a space
		    ## separated list of supported sample rates
		    printf "%s:%s\n" "${rawformat}" "${sorted_rates%*,}"
		done
	    fi
	else
	    ## in use by another process
	    ## res contains pid,cmd of locking process
	    locking_pid="${res%,*}"
	    locking_cmd="${res#*,}"
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "\
device is in use by command ${locking_cmd} with process id ${locking_pid}."
	    ## return the error instead of the formats
	    printf "by command \`%s' with PID %s." \
		   "${locking_cmd}" "${locking_pid}"
	    return 1  
	fi
    fi
}

function return_alsa_uac_ep() {
    ## returns the usb audio class endpoint as a fixed number.
    ## needs path to stream file as single argument ($1)
    ## based on ./sound/usb/proc.c:
    ##  printf "    Endpoint: %d %s (%s)\n",
    ##   1: fp->endpoint & USB_ENDPOINT_NUMBER_MASK (0x0f) > [0-9]
    ## TODO: unsure which range this is; have seen 1, 3 and 5
    ##   2: USB_DIR_IN: "IN|OUT",
    ##   3: USB_ENDPOINT_SYNCTYPE: "NONE|ASYNC|ADAPTIVE|SYNC"
    alsa_if_streamfile_path="$1"
    ep_mode=""
    ep_label_filter="Endpoint:"
    ep_label_regexp="^[[:space:]]*${ep_label_filter}"
    ep_num_filter="([0-9]+)"                         #1
    ep_num_regexp="[[:space:]]${ep_num_filter}"
    ep_direction_filter="OUT"
    ep_direction_regexp="[[:space:]]${ep_direction_filter}"
    ep_synctype_filter="(${UO_EP_NONE_FILTER}|${UO_EP_ADAPT_FILTER}|${UO_EP_ASYNC_FILTER}|${UO_EP_SYNC_FILTER})"                                   #2
    ep_synctype_regexp="[[:space:]]\(${ep_synctype_filter}\)$"
    ep_regexp="${ep_label_regexp}${ep_num_regexp}${ep_direction_regexp}${ep_synctype_regexp}"
    ## iterate the contents of the streamfile
    while read -r line; do
	if [[ "${line}" =~ ${ep_regexp} ]]; then
	    ep_mode="${BASH_REMATCH[2]}"
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "matching endpoint found in line \`${line}': \`${ep_mode}'."
	    break
	fi
    done<"${alsa_if_streamfile_path}"
    if [[ "${ep_mode}x" == "x" ]]; then
	[[ ${DEBUG} ]] && \
	    debug "${LINENO}" "no matching endpoints found. ${MSG_ERROR_UNEXPECTED}"
	return 1
    else
	## return the filtered endpoint type
	printf "%s" "${ep_mode}"
    fi
}


### command line parsing

function analyze_opt_limit() {
    ## check if the argument for the `-l' (limit) option is proper
    option="$1"
    opt_limit="${2-}"
    declare -a args
    prev_opt=0
    declare msg
    case ${opt_limit} in
        a|analog)
	    OPT_LIMIT_AO="True"
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "OPT_LIMIT_AO set to \`${OPT_LIMIT_AO}'"
	    return 0
	    ;;
        u|usb|uac)
	    OPT_LIMIT_UO="True"
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "OPT_LIMIT_UO set to \`${OPT_LIMIT_UO}'"
	    return 0
	    ;;
        d|digital)
	    OPT_LIMIT_DO="True"
	    [[ ${DEBUG} ]] && \
		debug "${LINENO}" "OPT_LIMIT_DO set to \`${OPT_LIMIT_DO}'"
	    return 0
	    ;;
	*)
	    ## construct list of option pairs: "x (or 'long option')"
	    for arg_index in "${!OPT_LIMIT_ARGS[@]}"; do
		if [[ $(( arg_index % 2)) -eq 0 ]]; then
		    ## even (short option): new array item
		    args+=("")
		else
		    ## odd (long option): add value to previous array item
		    prev_opt=$(( arg_index - 1 ))
		    args[-1]="${OPT_LIMIT_ARGS[${prev_opt}]} (or '${OPT_LIMIT_ARGS[${arg_index}]}')"
		fi
	    done
	    args_val=$(printf "%s, " "${args[@]}")
	    # shellcheck disable=SC2059
	    msg_vals="$(printf " ${args_val%*, }\n")"
	    msg_custom="maybe you could try to use the custom filter option, eg:"
	    msg_trail="for limit option \`${option}' specified. should be one of:\n"
	    if [[ ! -z ${opt_limit} ]]; then
		str_re=""
		for (( i=0; i<${#opt_limit}; i++ )); do
		    char="${opt_limit:$i:1}"
		    str_re+="[${char^^}${char,,}]"
		done
		msg="invalid value \`${opt_limit}' "
		# shellcheck disable=SC2059
		msg+="$(printf "${msg_trail}${msg_vals}\n${msg_custom}")"
		## display instructions to use the custom filter
		msg+="$(printf "\n bash $0 -c \"%s\"\n" "${str_re}")"
	    else
		# shellcheck disable=SC2059
		msg="$(printf "no value for ${msg_trail}${msg_vals}")"
	    fi

	    ## display the option pairs, stripping the trailing comma
	    printf "%s\n" "${msg}" 1>&2;
	    exit 1
    esac
}


function display_usageinfo() {
    ## display syntax and exit
    msg=$(cat <<EOF
Usage:
${APP_NAME_AC} [ -l a|d|u ]  [ -c <filter> ] [-a <hwaddress>] [-s] [ -q ]

Displays a list of each alsa audio output interface with its details
including its alsa hardware address (\`hw:x,y').

The list may be filtered by using the limit option \`-l' with an
argument to only show interfaces that fit the limit. In addition, a
custom filter may be specified as an argument for the \`c' option.

The \`-q (quiet)' and \`-a (address)' options are meant for usage in
other scripts. The script returns 0 on success or 1 in case of no
matches or other errors.

  -l TYPEFILTER, --limit TYPEFILTER
                     Limit the interfaces to TYPEFILTER. Can be one of
                     \`a' (or \`analog'), \`d' (or \`digital'), \`u'
                     (or \`usb'), the latter for USB Audio Class (UAC1
                     or UAC2) devices.
  -c REGEXP, --customlimit REGEXP
                     Limit the available interfaces further to match
                     \`REGEXP'.
  -a HWADDRESS, --address HWADDRESS
                     Limit the returned interface further to the one
                     specified with HWADDRESS, eg. \`hw:0,1'
  -s, --samplerates  Adds a listing of the supported sample rates for
                     each format an interface supports.
                     CAUTION: Besides being slow this option
                              PLAYS NOISE ON EACH OUTPUT!
  -q, --quiet        Surpress listing each interface with its details,
                     ie. only store the details of each card in the
                     appropriate arrays.
  -h, --help         Show this help message

Version ${APP_VERSION}. For more information see:
${APP_INFO_URL}
EOF
       )
    printf "%s\n" "${msg}" 1>&2;
}


function analyze_command_line() {
    ## parse command line arguments using the `manual loop` method
    ## described in http://mywiki.wooledge.org/BashFAQ/035.
    while :; do
        case "${1:-}" in
            -l|--limit)
		if [ -n "${2:-}" ]; then
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "$(printf "option \`%s' set to \`%s'.\n" "$1" "$2")"
		    analyze_opt_limit "$1" "$2"
		    shift 2
                    continue
		else
		    analyze_opt_limit "$1"
                    exit 1
		fi
		;;
	    -c|--customfilter)
		if [ -n "${2:-}" ]; then
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "$(printf "option \`%s' set to \`%s'.\n" "$1" "$2")"
		    OPT_CUSTOMFILTER="${2}"
		    shift 2
                    continue
		else
                    printf "ERROR: option \`%s' requires a non-empty argument.\n" "$1" 1>&2
                    exit 1
		fi
		;;
            -a|--address)
		if [ -n "${2:-}" ]; then
		    [[ ${DEBUG} ]] && \
			debug "${LINENO}" "option \`$1' set to \`$2'"
		    OPT_HWFILTER="$2"
		    shift 2
                    continue
		else
                    printf "ERROR: option \`%s' requires a alsa hardware address \
as an argument (eg \`hw:x,y')\n" "$1" 1>&2
                    exit 1
		fi
		;;
            -s|--samplerates)
		## deprecated
		[[ ${DEBUG} ]] && \
		    debug "${LINENO}" "option \`$1' set"
		OPT_SAMPLERATES=true
		shift
                continue
		;;
	    -q|--quiet|--silent)
		[[ ${DEBUG} ]] && \
		    debug "${LINENO}" "option \`$1' set"
		OPT_QUIET=true
		shift
                continue
		;;
	    -j|--json)
		OPT_JSON=true
		shift
                continue
		;;
	    -h|-\?|--help)
		display_usageinfo
		exit
		;;
            --)
		shift
		break
		;;
	    -?*)
		printf "Notice: unknown option \`%s' ignored\n\n." "$1" 1>&2
		display_usageinfo
		exit
		;;
            *)
		break
        esac
    done
}


function return_alsa_interface() {
    ## main function; see display_usageinfo()
    profile_file=
    ## start profiling
    if [[ ${PROFILE} ]]; then
	profile_file="/tmp/alsa-capabilities.$$.log"
	PS4='+ $(date "+%s.%N")\011 '
	exec 3>&2 2>${profile_file}
	set -x
    fi
    ## check if needed commands are available
    CMD_PASUSPENDER=$(type -p pasuspender)
    CMD_APLAY="$(type -p aplay)" || \
	command_not_found "aplay" "alsa-utils"
    if [[ "${CMD_PASUSPENDER}x" != "x" ]]; then 
	CMD_APLAY="${CMD_PASUSPENDER} -- ${CMD_APLAY}"
    fi
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
	die "The script cannot continue without aplay."
    else
	[[ ${DEBUG} ]] && \
	    debug "${LINENO}" "Using \`${CMD_APLAY}' as aplay command."
    fi
    ## parse command line arguments
    analyze_command_line "$@"
    ## create a list of alsa audio output interfaces and parse it.
    fetch_alsa_outputinterfaces
    ## exit with error if no matching output line was found
    if [[ ${#ALSA_AIF_HWADDRESSES[@]} -eq 0 ]]; then
	msg="\n${MSG_MATCH_IF_NONE_UNLIMITED}"
	##  display information about the number of interfaces before filtering
	if [[ ${NR_AIFS_BEFOREFILTERING} -ne 0 ]]; then
	    # shellcheck disable=SC2059
            printf -v msg "${msg}\n${MSG_MATCH_IF_NONE_LIMITED}" \
			 "${NR_AIFS_BEFOREFILTERING}"
	    printf  1>&2 "%s\n" "${msg}"
	fi
    fi
    [[ ${DEBUG} ]] && \
	debug "${LINENO}" "Number of audio interfaces after filtering: \
 ${#ALSA_AIF_HWADDRESSES[@]}"
    if [[ ${PROFILE} ]]; then
	## end profiling
	set +x
	exec 2>&3 3>&-
	debug "${LINENO}" "Profiling information stored in: ${profile_file}"
    fi
    ## return success if interfaces are found
    return 0
}

### global variables

## indexed arrays to store the details of interfaces of one would
## declare such an array in another script, that array would be filled
## instead of these. See examples/bash-example.sh for usage.
set +u

[[ "${ALSA_AIF_HWADDRESSES[*]}x" == "x" ]] && declare -a ALSA_AIF_HWADDRESSES=()
[[ "${ALSA_AIF_DISPLAYTITLES[*]}x" == "x" ]] && declare -a ALSA_AIF_DISPLAYTITLES=()
[[ "${ALSA_AIF_MONITORFILES[*]}x" == "x" ]] && declare -a ALSA_AIF_MONITORFILES=()
[[ "${ALSA_AIF_DEVLABELS[*]}x" == "x" ]] && declare -a ALSA_AIF_DEVLABELS=()
[[ "${ALSA_AIF_LABELS[*]}" == "x" ]] && declare -a ALSA_AIF_LABELS=()
[[ "${ALSA_AIF_UACCLASSES[*]}x" == "x" ]] && declare -a ALSA_AIF_UACCLASSES=()
[[ "${ALSA_AIF_FORMATS[*]}x" == "x" ]] && declare -a ALSA_AIF_FORMATS=()
[[ "${ALSA_AIF_CHARDEVS[*]}x" == "x" ]] && declare -a ALSA_AIF_CHARDEVS=()

set -u

## counter for unfiltered interfaces
NR_AIFS_BEFOREFILTERING=0
NR_AIFS_AFTERFILTERING=0

## static filter for digital interfaces
DO_FILTER_LIST="$(cat <<EOF
adat
aes
ebu
digital
dsd
hdmi
i2s
iec958
spdif
s/pdif
toslink
uac
usb
EOF
    )"

## construct static list of sample rates
## based on ground clock frequencies of
##  - video standard: 24.576  (mHz) * 1000000 / 512 = 48000Hz
##  - audio standard: 22.5792 (mHz) * 1000000 / 512 = 44100Hz

base_fs_video=$(( 24576000 / 512 ))
base_fs_audio=$(( 22579200 / 512 ))
## initialize audio rates with fs*1 (cd)
declare -a SAMPLERATES_AUDIO
#=(${base_fs_audio})
## initalize video rates with base * 2/3 (which seems common)
declare -a SAMPLERATES_VIDEO
#=($(( base_fs_video * 2 / 3 )) ${base_fs_video})

## max multiplier: fs*n
max_fs_n=8
n=${max_fs_n};
while [[ ${n} -ge 1 ]]; do
    video_rate=$(( base_fs_video * n ))
    SAMPLERATES_VIDEO+=(${video_rate})
    audio_rate=$(( base_fs_audio * n ))
    SAMPLERATES_AUDIO+=(${audio_rate})
    n=$(( n / 2 ))
done

## pseudo audio data to generate (silent) noise
PSEUDO_SILENT_AUDIO="00000000000000000000000000000000000000000000"
declare -a DO_INTERFACE_FILTER=($(printf -- '%s' "${DO_FILTER_LIST// /" "}"))

## construction for displayed output
UAC="USB Audio Class"
ALSA_IF_LABEL="alsa audio output interface"
declare -A ALSA_IF_LABELS=()
ALSA_IF_LABELS+=(["ao"]="Analog ${ALSA_IF_LABEL}")
ALSA_IF_LABELS+=(["do"]="Digital ${ALSA_IF_LABEL}")
ALSA_IF_LABELS+=(["uo"]="${UAC} ${ALSA_IF_LABELS[do]}")

## USB_SYNC_TYPEs
## strings alsa uses for UAC endpoint descriptors.
## one of *sync_types "NONE", "ASYNC", "ADAPTIVE" or "SYNC" according
## to ./sound/usb/proc.c
UO_EP_NONE_FILTER="NONE"
UO_EP_ADAPT_FILTER="ADAPTIVE"
UO_EP_ASYNC_FILTER="ASYNC"
UO_EP_SYNC_FILTER="SYNC"
## labels for UAC classes.
UO_EP_NONE_LABEL="0 - none"
UO_EP_ADAPT_LABEL="1 - isochronous adaptive"
UO_EP_ASYNC_LABEL="2 - isochronous asynchronous"
UO_EP_SYNC_LABEL="3 - sync (?)"
## declarative array holding the available UAC classes with
## description
declare -A UO_EP_LABELS=( ["${UO_EP_NONE_FILTER}"]="${UO_EP_NONE_LABEL}"
			  ["${UO_EP_ADAPT_FILTER}"]="${UO_EP_ADAPT_LABEL}"
			  ["${UO_EP_ASYNC_FILTER}"]="${UO_EP_ASYNC_LABEL}"
			  ["${UO_EP_SYNC_FILTER}"]="${UO_EP_SYNC_LABEL}" )

## system messages
MSG_PROP_NOTAPPLICABLE="(n/a)"
MSG_ERROR_GETTINGFORMATS="can't detect formats or rates because device is in use"
MSG_ERROR_NOFILE="is not a file or is not accessible."
MSG_ERROR_UNEXPECTED="THIS SHOULD NOT HAPPEN."
MSG_APLAY_ERROR_NOSOUNDCARDS="aplay did not find any soundcard."
MSG_APLAY_ERROR_GENERAL="aplay reported the following error:\n\`%s'"
MSG_APLAY_USINGTESTFILE="NOTICE: using fake aplay output stored in TESTFILE: \`%s'."
MSG_APLAY_ERROR_NOSUCHTESTFILE="Specified TESTFILE \'%s' does not exist."
MSG_APLAY_ERROR_OPENINGTESTFILE="Error opening TESTFILE \'%s'."
MSG_MATCH_IF_NONE_UNLIMITED=" * No ${ALSA_IF_LABEL}s found."
MSG_MATCH_IF_NONE_LIMITED=" * From the %s available ${ALSA_IF_LABEL}s, \
none matched your filter."
MSG_ERROR_CHARDEV_NOFORMATS="can't determine: character device error"
MSG_ERROR_NOT_CHARDEV="error: is not a character device or not accessible"
## construct a list with the properties of the current
## interface if `OPT_QUIET' is not set
MSG_ALSA_DEVNAME="device name"
MSG_ALSA_IFNAME="interface name"
MSG_ALSA_UACCLASS="usb audio class"
MSG_ALSA_CHARDEV="character device"
MSG_ALSA_ENCODINGFORMATS="encoding formats"
MSG_ALSA_MONITORFILE="monitor file"
MSG_ALSA_STREAMFILE="stream file"

## command line options
## input parameters for the limit option
## should be consequtive pairs of '"x" "long option"'
declare -a OPT_LIMIT_ARGS=("a" "analog" "d" "digital" "u" "usb")
## also see analyze_command_line
OPT_LIMIT_AO=${OPT_LIMIT_AO:-}
OPT_LIMIT_DO=${OPT_LIMIT_DO:-}
OPT_LIMIT_UO=${OPT_LIMIT_UO:-}
OPT_QUIET=${OPT_QUIET:-}
OPT_JSON=${OPT_JSON:-}
OPT_CUSTOMFILTER=${OPT_CUSTOMFILTER:-}
OPT_HWFILTER=${OPT_HWFILTER:-}
OPT_SAMPLERATES=${OPT_SAMPLERATES:-}

## if the script is not sourced by another script but run within its
## own shell call function `return_alsa_interface'
[[ "${BASH_SOURCE[0]:-}" != "${0}" ]] || \
    return_alsa_interface "$@"
