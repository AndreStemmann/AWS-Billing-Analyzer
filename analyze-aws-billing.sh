#!/bin/bash

# author: andre stemmann
# date: 	2017-06-09
# desc:		script to download and process aws cost allocation reports
# prerequisites
#  - awscli
#  - existing S3 bucket with cost allocation reports
#  - programmatic access to the related S3 bucket
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.

usage() {
  echo "$0"
  echo "----------------"
  echo "mandatory parameter:"
  echo "---------------------"
  echo "--AK=<string>  : AWS access key"
  echo "--SK=<string>  : AWS secret access key"
  echo "--BN=<string>  : AWS S3 bucket name"
  echo "--RE=<string>  : AWS region e.g. us-west-2"
  echo "--DST=<string> : Where/to/store/billing/reports/from/aws"
  echo ""
  echo " Type --help (-h) for more information"
  echo ""
}
printHelp() {
  echo "These are the parameters needed to call the script for basic,"
  echo "summarized costs per AWS account e.g. for automated reports or quick overview"
  echo "-----------------------------------------------------------------------------"
  echo "--AK=<string>  : AWS access key"
  echo "AWS access key is for programmatic S3 access and gets provided by AWS to you"
  echo ""
  echo "--SK=<string>  : AWS secret access key"
  echo "AWS secret access key is also provided by AWS to you together with the AK"
  echo ""
  echo "--BN=<string>  : AWS S3 bucket name where the cost-allocation reports are stored"
  echo "The name of the S3 bucket you created to store your billing reports"
  echo ""
  echo "--RE=<string>  : AWS region e.g. us-west-2"
  echo "Just a region parameter in case you provided another one to your awscli"
  echo ""
  echo "--DST=<string> : Where/to/store/billing/reports/from/aws"
  echo "Please provide the path where you want to save the downloaded reports"
  echo "Your final, analyzed report based on the downloaded files,"
  echo "will be stored in echo $(pwd)"
  echo ""
  echo "These are the optional parameters to make the script a bit more comfortable"
  echo "---------------------------------------------------------------------------"
  echo "--DL=<string> : Download only? [y]es. Default is download and analyze latest report"
  echo "Provide this extra-parameter if you only want to download the files,"
  echo "from AWS S3 Bucket but do not analyze them"
  echo ""
  echo "--AF=<date>   : Analyze file with specific date e.g. 2017-05. Default is the latest report"
  echo "Use this parameter to evaluate the costs for a specific report, not only the latest"
  echo ""
  echo "--OP=<string> : [I]nteractive output. Default is print out everthing"
  echo "If this parameter is given, an interactive menu will be created, based"
  echo "on the AWS accounts from your billing-report."
  echo ""
  echo "--TG=<string>  : AWS tag to search for e.g. user:<MyTag>. Only to use with --OP Parameter"
  echo "This parameter can be used additional to the --OP-param to make the report"
  echo "a bit more detailed. First you choose your account, then one of the tags"
  echo ""
  echo "Again - your analyzed Reportfiles will be alawys stored to $(pwd)"
  echo ""
  echo "example call to download and analyze the latest file with default total account output and tag user:component:"
  echo "./aws_billing.sh --AK=ASDFDF --SK=DFDFDFD --BN=billing-bucket --RE=us-west-2 --DST=/home/user/here/"
  echo ""
  echo "example call to only download the files:"
  echo "./aws_billing.sh --AK=ASDFDF --SK=DFDFDFD --BN=billing-bucket --RE=us-west-2 --DST=/home/user/here/ --DL=yes"
  echo ""
  echo "example call to download and analyze the report for 2017-06"
  echo "./aws_billing.sh --AK=ASDFDF --SK=DFDFDFD --BN=billing-bucket --RE=us-west-2 --DST=/home/user/here/ --AF=2017-05"
  echo""
  echo "example call to download and analyze the report for 2017-05 and perform interactive output with tagged components"
  echo "./aws_billing.sh --AK=ASDFDF --SK=DFDFDFD --BN=billing-bucket --RE=us-west-2 --DST=/home/user/here/ --AF=2017-05 --OP=yes"
  echo ""
  echo "example call to download and analyze the report for 2017-05 and perform interactive output with choosed tag"
  echo "./aws_billing.sh --AK=ASDFDF --SK=DFDFDFD --BN=billing-bucket --RE=us-west-2 --DST=/home/user/here/ --AF=2017-05 --OP=y --TG=y"
}

# catch an empty call
if [ $# -eq 0 ] ; then
  echo
  echo "no parameters are given!"
  echo
  usage
  exit 1
fi

if [ "$1" == "-h" ]; then
  printHelp
  exit 0
fi

if [ "$1" == "--help" ]; then
  printHelp
  exit 0
fi

# check if awscli is installed
hash aws
if [ $? -ne 0 ] ; then
  echo "aws is required in order to access the API"
  while true
  do
    echo " "
    echo "Do you want to install awscli now?"
    sleep 5
    read -p "Whether type Yes or No: " inst
    echo " "
    case "$inst" in
      [yY]* )
        echo "yes"
        if [[ $(id -u -n) = "root" ]]; then
          apt-get update && sudo apt-get install awscli -y
          if [ $? -ne 0 ]; then
            echo "apt-get install failed, will pull it via wget"
            wget https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -P "$(pwd)"
            if [ $? -ne 0 ]; then
              echo "wget failed equally. Check your internet cnx. aborting"
              exit 1
            else
              unzip "$(pwd)"/awscli-bundle.zip
              ./awscli-bundle/install -b ~/bin
              export PATH=~/bin:$PATH
            fi
          fi
        else
          echo "In order to install the awscli you need to be root"
          echo "Please run the script again as root during awscli installation"
          echo "exiting..."
          exit 1
        fi
        ;;
      [nN]* )
        echo "OK, aborting without installing awscli"
        exit 1
        break;;
      *) echo "Invalid, please answer Yes or No";;
    esac
  done
fi
# parse parameters
until [[ ! "$*" ]]; do
  if [[ ${1:0:2} = '--' ]]; then
    PAIR="${1:2}"
    PARAMETER=$(echo "${PAIR%=*}" | tr '[:lower:]' '[:upper:]')
    eval P_"$PARAMETER"="${PAIR##*=}"
  fi
  shift
done

# check if all parameters are given
if   [ -z "$P_AK" ] ; then
  echo "ERROR: please specify the AK - parameter"
  echo "exiting script..."
  exit 1
elif [ -z "$P_SK" ] ; then
  echo "ERROR: please specify the SK - parameter"
  echo "exiting script..."
  exit 1
elif [ -z "$P_BN" ] ; then
  echo "ERROR: please specify the BN - parameter"
  echo "exiting script..."
  exit 1
elif [ -z "$P_DST" ] ; then
  echo "ERROR: please specify the DST - parameter"
  echo "exiting script..."
  exit 1
elif [ -z "$P_RE" ] ; then
  echo "ERROR: please specify the RE - parameter"
  echo "exiting script..."
  exit 1
elif [ ! -z "$P_DL" ] ; then
  if [ ! -d "$P_DST" ]; then
    mkdir -p "$P_DST"
  fi
  # download only reports
  AWS_ACCESS_KEY_ID=$P_AK AWS_SECRET_ACCESS_KEY=$P_SK AWS_DEFAULT_REGION=$P_RE aws s3 sync s3://"${P_BN}"/	"${P_DST}"
  exit 0
else
  if [ ! -d "$P_DST" ]; then
    mkdir -p "$P_DST"
  fi
  # download reports and analyze
  AWS_ACCESS_KEY_ID=$P_AK AWS_SECRET_ACCESS_KEY=$P_SK AWS_DEFAULT_REGION=$P_RE aws s3 sync s3://"${P_BN}"/ "${P_DST}"
  if [ ! -z "$P_AF" ] ; then
    name=$(find "${P_DST}" -iname "*aws-cost-allocation-${P_AF}.csv")
  else
    name=$(ls -1rt "${P_DST}"/*.csv|tail -1)
  fi
  outname=$(echo "$name"|rev |cut -d"/" -f1|rev|cut -d"-" -f5-6)

  if [ -z "$P_OP" ] && [ ! -z "$P_TG" ] ; then
    echo "Error, If you choose the tag selection, you also have to choose the account selection (--OP=)"
    exit 1
  elif [ ! -z "$P_OP" ] && [ ! -z "$P_TG" ] ; then
    # tag selection
    tag ()
    {
      select tags; do
        if [ "$REPLY" -gt "$#" ]; then
          echo "Incorrect Input: Select a number 1-$#"
          break;
        elif [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#-1)) ] || [ "$REPLY" -eq "$#" ]; then
          headers=$(awk -v header="${tags}" 'BEGIN { FS="^\"|\",\"|\"$"; OFS="\t"; c=0 } { if(NR==2) { for (i=1;i<=NF;i++) { c++;if($i==header){print c} }}}' "$name")
          echo "Selected menu number ${REPLY} selected tag name ${tags} selected column number ${headers}"
          break;
        else
          echo "Incorrect Input: Select a number 1-$#"
          break;
        fi
      done
    }
    TAGS=($(awk 'BEGIN { FS="^\"|\",\"|\"$"; OFS="\t"; c=0 } { if(NR==2) { for (i=1;i<=NF;i++) { print $i }}}' "$name"))
    tag "${TAGS[@]}"

    awk -v column="${headers}" 'BEGIN {FS="^\"|\",\"|\"$"; OFS="\t";} {if($5=="LinkedLineItem") { summe[$11,tolower($column)] += $31; }} END{for (i in summe) {split(i,c,SUBSEP); if(c[2]==""){c[2]="untagged";} printf("%s%s%s%s%'\''.2f\n",c[1],OFS,c[2],OFS,summe[i]);}}' "$name"|sort -h > detailed_costs_per_account_"${outname}"

    # account selection
    account ()
    {
      select accounts; do
        if [ "$REPLY" -gt "$#" ]; then
          echo "Incorrect Input: Select a number 1-$#"
          break;
        elif [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#-1)) ] || [ "$REPLY" -eq "$#" ]; then
          awk -v accounts="$accounts" 'BEGIN {FS="\t";OFS="\t";} {if($1==accounts) {print $0}}' detailed_costs_per_account_"${outname}" | column -ts$'\t'
          break;
        else
          echo "Incorrect Input: Select a number 1-$#"
          break;
        fi
      done
    }
    oldifs="$IFS"
    IFS=$'\n'
    ACCOUNTS=( $(cut -d$'\t' -f1 detailed_costs_per_account_"${outname}"|sort -u))
    IFS="$oldifs"
    account "${ACCOUNTS[@]}"

  elif [ ! -z "$P_OP" ] && [ -z "$P_TG" ] ; then
    # create detailed account report for interactive ouput
    awk 'BEGIN {FS="^\"|\",\"|\"$"; OFS="\t";} {if($5=="LinkedLineItem") {summe[$11,tolower($40)] += $31;}}END{for (i in summe) {split(i,c,SUBSEP); if(c[2]==""){c[2]="untagged";} printf("%s%s%s%s%'\''.2f\n",c[1],OFS,c[2],OFS,summe[i]);}}' "$name"|sort -h > detailed_costs_per_account_"${outname}"
    # output selection
    createmenu ()
    {
      select option; do
        if [ "$REPLY" -gt "$#" ]; then
          echo "Incorrect Input: Select a number 1-$#"
          break;
        elif [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#-1)) ] || [ "$REPLY" -eq "$#" ]; then
          awk -v option="$option" 'BEGIN {FS="\t";OFS="\t";} {if($1==option) {print $0}}' detailed_costs_per_account_"${outname}"| column -ts$'\t'
          break;
        else
          echo "Incorrect Input: Select a number 1-$#"
          break;
        fi
      done
    }

    oldifs="$IFS"
    IFS=$'\n'
    OPTIONS=( $(cut -d$'\t' -f1 detailed_costs_per_account_"${outname}"|sort -u))
    IFS="$oldifs"
    createmenu "${OPTIONS[@]}"

  else
    # general output
    echo ""
    echo "Total costs_per_account_${outname}"
    echo "#############################"
    echo ""
    # create total account report
    awk 'BEGIN{FS="^\"|\",\"|\"$";OFS="\t"}{if($5=="AccountTotal") {printf("%s%s%'\''.2f\n",$11,OFS,$31)}}' "$name"|sort -h > total_costs_per_account_"${outname}"
    column -ts$'\t' total_costs_per_account_"${outname}"|| sort
  fi
fi
exit 0
