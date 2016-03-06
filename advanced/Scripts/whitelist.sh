#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Whitelists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

if [[ $# = 0 ]]; then
    echo "Immediately whitelists one or more domains in the hosts file"
    echo " "
    echo "Usage: whitelist.sh domain1 [domain2 ...]"
    echo "  "
    echo "Options:"
    echo "  -d, --delmode		Remove domains from the whitelist"
    echo "  -nr, --noreload	Update Whitelist without refreshing dnsmasq"
    echo "  -f, --force		Force updating of the hosts files, even if there are no changes"
    echo "  -q, --quiet		output is less verbose"
    exit 1
fi

#globals
whitelist=/etc/pihole/whitelist.txt
adList=/etc/pihole/gravity.list
reload=true
addmode=true
force=false
versbose=true
domList=()
domToRemoveList=()

piholeIPfile=/tmp/piholeIP
piholeIPv6file=/etc/pihole/.useIPv6

# Otherwise, the IP address can be taken directly from the machine, which will happen when the script is run by the user and not the installation script
IPv4dev=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
piholeIPCIDR=$(ip -o -f inet addr show dev $IPv4dev | awk '{print $4}' | awk 'END {print}')
piholeIP=${piholeIPCIDR%/*}

modifyHost=false


if [[ -f $piholeIPv6file ]];then
    # If the file exists, then the user previously chose to use IPv6 in the automated installer
    piholeIPv6=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
fi


function HandleOther(){
  #check validity of domain
	validDomain=$(echo $1 | perl -ne'print if /\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b/')

	if [ -z "$validDomain" ]; then
		echo "::: $1 is not a valid argument or domain name"
	else
	  domList=("${domList[@]}" $validDomain)
	fi
}

function PopWhitelistFile(){
	#check whitelist file exists, and if not, create it
	if [[ ! -f $whitelist ]];then
  	  touch $whitelist
	fi
	for dom in "${domList[@]}"
	do
	  if $addmode; then
	  	AddDomain $dom
	  else
	    RemoveDomain $dom
	  fi
	done
}

function AddDomain(){
#| sed 's/\./\\./g'
	bool=false

	grep -Ex -q "$1" $whitelist || bool=true
	if $bool; then
	  #domain not found in the whitelist file, add it!
	  if $versbose; then
		echo -n "::: Adding $1 to whitelist.txt..."
	  fi
	  echo $1 >> $whitelist
		modifyHost=true
		if $versbose; then
	  	echo " done!"
	  fi
	else
		if $versbose; then
			echo "::: $1 already exists in whitelist.txt, no need to add!"
		fi
	fi
}

function RemoveDomain(){

  bool=false
  grep -Ex -q "$1" $whitelist || bool=true
  if $bool; then
  	#Domain is not in the whitelist file, no need to Remove
  	if $versbose; then
  	echo "::: $1 is NOT whitelisted! No need to remove"
  	fi
  else
    #Domain is in the whitelist file, add to a temporary array and remove from whitelist file
    #if $versbose; then
    #echo "::: Un-whitelisting $dom..."
    #fi
    domToRemoveList=("${domToRemoveList[@]}" $1)
    modifyHost=true
  fi
}

function ModifyHostFile(){
	 if $addmode; then
	    #remove domains in  from hosts file
	    if [[ -r $whitelist ]];then
        # Remove whitelist entries
				numberOf=$(cat $whitelist | sed '/^\s*$/d' | wc -l)
        plural=; [[ "$numberOf" != "1" ]] && plural=s
        echo ":::"
        echo -n "::: Modifying HOSTS file to whitelist $numberOf domain${plural}..."
        awk -F':' '{print $1}' $whitelist | while read line; do echo "$piholeIP $line"; done > /etc/pihole/whitelist.tmp
        awk -F':' '{print $1}' $whitelist | while read line; do echo "$piholeIPv6 $line"; done >> /etc/pihole/whitelist.tmp
        echo "l" >> /etc/pihole/whitelist.tmp
        grep -F -x -v -f /etc/pihole/whitelist.tmp /etc/pihole/gravity.list > /etc/pihole/gravity.tmp
        rm /etc/pihole/gravity.list
        mv /etc/pihole/gravity.tmp /etc/pihole/gravity.list
        rm /etc/pihole/whitelist.tmp
        echo " done!"

	  	fi
	  else
	    #we need to add the removed domains to the hosts file
	    echo ":::"
	    echo "::: Modifying HOSTS file to un-whitelist domains..."
	    for rdom in "${domToRemoveList[@]}"
	    do
	    	if [[ -n $piholeIPv6 ]];then
	    	  echo -n ":::    Un-whitelisting $rdom on IPv4 and IPv6..."
	    	  echo $rdom | awk -v ipv4addr="$piholeIP" -v ipv6addr="$piholeIPv6" '{sub(/\r$/,""); print ipv4addr" "$0"\n"ipv6addr" "$0}' >> $adList
	    	  echo " done!"
	      else
	        echo -n ":::    Un-whitelisting $rdom on IPv4"
	      	echo $rdom | awk -v ipv4addr="$piholeIP" '{sub(/\r$/,""); print ipv4addr" "$0}' >>$adList
	      	echo " done!"
	      fi
	      echo -n ":::        Removing $rdom from whitelist.txt..."
	      echo $rdom| sed 's/\./\\./g' | xargs -I {} perl -i -ne'print unless /'{}'(?!.)/;' $whitelist
	      echo " done!"
	    done
	  fi
}

function Reload() {
	# Reload hosts file
	echo ":::"
	echo -n "::: Refresh lists in dnsmasq..."
	dnsmasqPid=$(pidof dnsmasq)

	if [[ $dnsmasqPid ]]; then
		# service already running - reload config
		sudo kill -HUP $dnsmasqPid
	else
		# service not running, start it up
		sudo service dnsmasq start
	fi
	echo " done!"
}

###################################################

for var in "$@"
do
  case "$var" in
    "-nr"| "--noreload"  ) reload=false;;
    "-d" | "--delmode"   ) addmode=false;;
    "-f" | "--force"     ) force=true;;
    "-q" | "--quiet"     ) versbose=false;;
    *                    ) HandleOther $var;;
  esac
done

PopWhitelistFile

if $modifyHost || $force; then
	 ModifyHostFile
else
  if $versbose; then
  echo ":::"
	echo "::: No changes need to be made"
	exit 1
	fi
fi

if $reload; then
	Reload
fi
