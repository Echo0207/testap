#!/bin/bash
#============================================================================================
#        File: TestAP.sh
#    Function: Main program
#     Version: 1.2.0
#      Author: Cody,qiutiqin@msi.com
#     Created: 2018-07-02
#     Updated: 2020-11-18
#  Department: Application engineering course
# 		 Note: 1.1.0更新：項目的index不需連續也可以進行測試,方便PE debug
# 		       1.1.1更新：合并部分脚本到主程式
# 		       1.1.2更新：更新程式清單是否有對應的配置檔內容/XML格式更新for組合測試
# 		       1.1.3更新：ATA/BUS/Hardware Error等報錯修改為週期檢查
#		       1.2.0更新：lan_c,bmcmac_c,cmostime 测试一次fail就会上传并删除资料
#			         兼容python 脚本，可以直接调用python脚本（多进程不要使用）
#				 fail次数修改为可定义次数，建议定义次数为2次
# Environment: Linux/CentOS
#============================================================================================
#----Define sub function---------------------------------------------------------------------
Process()
{ 	
	local Status="$1"
	local String="$2"
	case ${Status} in
		0)printf "%-3s\e[1;32m%-2s\e[0m%-5s%-60s\n" "[  " "OK" "  ]  " "${String}";;
		*)printf "%-3s\e[1;31m%-2s\e[0m%-5s%-60s\n" "[  " "NG" "  ]  " "${String}" && return 1;;
		esac
	return 0
}

ShowTitle()
{
	local BlankCnt=0
	local Title="$@"
	let BlankCnt=(70-${#Title})/2
	BlankCnt=$(echo '                                           ' | cut -c 1-${BlankCnt})
	echo -e "\e[1m${BlankCnt}${Title}\e[0m"
}

ChkExternalCommands ()
{
	if [ $# == 0 ] ; then
		ExtCmmds=(xmlstarlet stat getCmosDST)
	else 
		ExtCmmds=(xmlstarlet $@ )
	fi
	for((c=0;c<${#ExtCmmds[@]};c++))
	do
	_ExtCmmd=$(command -v ${ExtCmmds[$c]})
	if [ $? != 0 ]; then
		Process 1 "No such tool or command: ${ExtCmmds[$c]}"
		let ErrorFlag++
	else
		chmod 777 ${_ExtCmmd}
	fi
	done
	[ ${ErrorFlag} != 0 ] && exit 127
	return 0
}

GetParametersFrXML ()
{
	xmlstarlet val "${XmlConfigFile}" >/dev/null 2>&1
	if [ $? != 0 ] ; then
		xmlstarlet fo ${XmlConfigFile}
		Process 1 "Invalid XML file: ${XmlConfigFile}"
		exit 3
	fi
	
	xmlstarlet sel -t -v "//ProgramName" -n "${XmlConfigFile}" 2>/dev/null | grep -iwq "${BaseName}"
	if [ $? != 0 ] ; then
		Process 1 "Thers's no configuration information for ${BaseName}.sh"
		exit 3
	fi
		
	local ConfigVersion=$(xmlstarlet sel -t -v "//MSITEST/@version"  -n "${XmlConfigFile}" 2>/dev/null) 
	if [ $(echo "${ConfigVersion}" | grep -iwc "${InternalVersion}") == 0 ] ; then
		Process 1 "使用了錯誤的xml版本, xml當前版本是: ${ConfigVersion}, 正確的版本是: ${InternalVersion}"
		exit 1
	fi

	# 從XML獲取參數
	ModelName=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ModelInfo/ModelName" -n "${XmlConfigFile}" 2>/dev/null)
	BiosFile=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ModelInfo/BiosFile" -n "${XmlConfigFile}" 2>/dev/null)
	BmcFile=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ModelInfo/BmcFile" -n "${XmlConfigFile}" 2>/dev/null)
	EepromFile=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ModelInfo/EepromFile" -n "${XmlConfigFile}" 2>/dev/null)
	MpsFW=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ModelInfo/MpsFW" -n "${XmlConfigFile}" 2>/dev/null)

	PTEName=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ReleaseInfo/PTEName" -n "${XmlConfigFile}" 2>/dev/null)
	ReleaseDate=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ReleaseInfo/ReleaseDate" -n "${XmlConfigFile}" 2>/dev/null)
	PEName=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ReleaseInfo/PEName" -n "${XmlConfigFile}" 2>/dev/null)
	Update=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ReleaseInfo/Update" -n "${XmlConfigFile}" 2>/dev/null)
	APVersion=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ReleaseInfo/APVersion" -n "${XmlConfigFile}" 2>/dev/null)
	StartIndex=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/StartIndex" -n "${XmlConfigFile}" 2>/dev/null)
	EndIndex=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/EndIndex" -n "${XmlConfigFile}" 2>/dev/null)
	StartParalle=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/StartParalle" -n "${XmlConfigFile}" 2>/dev/null)
	Encrypt=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/Encrypt/InUse" -n "${XmlConfigFile}" 2>/dev/null)
	EncryptPassword=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/Encrypt/Password" -n "${XmlConfigFile}" 2>/dev/null)
	CheckLogic=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/CheckLogic" -n "${XmlConfigFile}" 2>/dev/null)
	
	FailCntLimit=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/MaximumFailures" -n "${XmlConfigFile}" 2>/dev/null)
	FailLocking=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/FailLocking" -n "${XmlConfigFile}" 2>/dev/null)
	FailUpload=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/FailUpload" -n "${XmlConfigFile}" 2>/dev/null)
	IndexInUse=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/UrlAddress/IndexInUse" -n "${XmlConfigFile}" 2>/dev/null)
	NgLockWebSite=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/UrlAddress/NgLock[@index=${IndexInUse}]" -n "${XmlConfigFile}" 2>/dev/null)
	MesWebSite=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/UrlAddress/MesWeb[@index=${IndexInUse}]" -n "${XmlConfigFile}" 2>/dev/null)
	TestStation=$(xmlstarlet sel -t -v "//UpLoad/StationCode" -n "${XmlConfigFile}" 2>/dev/null)
	ErrorsOccurredChk=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ErrorsOccurredType/InUse" -n "${XmlConfigFile}" 2>/dev/null)

	if [ ${#ErrorsOccurredChk} != 0 ] ; then
		echo "${ErrorsOccurredChk}" | grep -iwq "enable\|disable" 
		if [ $? != 0 ] ; then
			Process 1 "Invalid ErrorsOccurredChk: ${ErrorsOccurredChk}"
			let ErrorFlag++
		fi
	else
		ErrorsOccurredChk='enable'
	fi
	
	if [ ${#ModelName} == 0 ] || [ ${#Update} == 0 ] ; then
		Process 1 "Error config file: ${XmlConfigFile}"
		let ErrorFlag++
	fi
	[ ${ErrorFlag} != 0 ] && exit 3
	return 0
}

CheckVbatAndCmostime ()
{
	local CurProcID=$1
	#確保測試過程中CMOS不被還原==>排除出電池未反向或未安裝、無電等情形
	echo ${CurProcID} | tr -d [A-Za-z] | grep -qE '[0-9]'
	if [ $? != 0 ] ; then
		echo "Usage: CheckVbatAndCmostime n"
		echo "		 n is current process id"
		exit 3
	fi

	if [ $((CurProcID%3)) == 1 ] ; then
		# 測項目為ClearRTC.sh則跳過檢查，ClearRTC測試pass後需要還原時間到原來的日期，否則到下一項測試檢查fail
		xmlstarlet sel -t -v  //Programs/Item[@index=${TotalItemIndex[CurProcID-1]}] ${XmlConfigFile} 2>/dev/null | grep -iwq "ClearRTC" && return 0
		CmostimeVal=$(date -d "`hwclock -r`" +%s)
		UpdateVal=$(date -d "${Update:-"2022-10-01"}" +%s)
		case ${CurProcID} in
			1)
				echo ${ModelName} | grep -q "^709" 2>/dev/null
				if [ $? != 0 ] && [  ${CmostimeVal} -lt ${UpdateVal}  ] ; then 
					date -s "${Update}" > /dev/null 2>&1
					hwclock -w > /dev/null 2>&1
					printf "%s\n" "The OS and hardware date has been reseted as: ${Update} 00:00:00"
				fi
			;;

			*)
				while [  "${CmostimeVal}" -lt "${UpdateVal}"  ]
				do
					echo -e "\e[30;41m ******************************************************************** \e[0m"
					echo -e "\e[30;41m *        Current Time : `date +"%Y-%m-%d %H:%M"`                      * \e[0m"
					echo -e "\e[30;41m *        CMOS date and time has been loaded default                * \e[0m"
					echo -e "\e[30;41m *        Please check the battery on board is reverse or lost ?    * \e[0m"
					echo -e "\e[30;41m ******************************************************************** \e[0m"
					read -p "Key [Q] to continue ..." -n1 Answer
					if [ ${Answers}x == "Q"x ] ; then
						trap '-' INT QUIT TSTP HUP
						echo
						echo -e "\e[1;33mPress [Ctrl]+[C] to exit ...\e[0m"
						read -t10 
						echo
					fi
				done
			;;
		esac
	fi
}

CheckSizeOfLog ()
{
	local TargetLog=$1
	#大於5MB的文件不給上傳FTP
	# Usage: CheckSizeOfLog logName
	local FileSize=$(stat -c "%s" ${TargetLog} 2>/dev/null)
	if [ ${FileSize:-"1048"} -gt 5242880 ] ; then
		Process 1 "The size of ${TargetLog} is too big(size=${FileSize} B, bigger than 5MB)"
		ls -lh ${TargetLog} 2>/dev/null
		exit 1
	fi
	return 0
}

IgnoreSpecTestItem()
{
	local ShellName="${1}"   #e.g.: ShellName=/TestAP/Bios/ChkBios.sh
	local ShellIndex="${2}"  #e.g.: ShellIndex=2
	local SuitForModels=()
		
	local ShellModelTable=($(xmlstarlet sel -t -v "//Programs/Item[@index=\"${ShellIndex}\"]/@model|//Programs/Item[@index=\"${ShellIndex}\"]" -n "${XmlConfigFile}" | sed ":a;N;s/.sh\n/.sh|/g;ba" ))
	SuitForModels=($(echo "${ShellModelTable[@]}" | tr ' ' '\n' | grep -w "${ShellName}" | awk -F'|' '{print $2}' | tr ',;' ' ' | grep -iwv "all" ))
	
	if [ "${#SuitForModels[@]}" == 0  ] ; then
		# if SuitForModels is null ,all model will run all items
		return 0
	fi

	# remove the ShellName
	local SoleSuitForModels=($(echo ${SuitForModels[@]} | tr ' ' '\n' | sort -u ))
	SoleSuitForModels=$(echo ${SoleSuitForModels[@]} | sed 's/ /\\|/g')
	local ModelSet=$(echo "${SoleSuitForModels}" | tr '|' ' ' | tr '\\ ' ' ' )
	cat -v "${MainDir}/PPID/SN_MODEL_TABLE.TXT" 2>/dev/null | grep -iq "${SoleSuitForModels}"
	if [ $? == 0 ] ; then
		printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
		printf "\e[0;30;43m%-6s%-60s%6s\e[0m\n" " **"  "${ShellName} is suitable for the model: ${ModelSet}"  "** "
		printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
	else
		printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
		printf "\e[0;30;43m%-6s%-60s%6s\e[0m\n" " **"  "No found the model: ${ModelSet}"  "** "
		printf "\e[0;30;43m%-6s%-60s%6s\e[0m\n" " **"  "${ShellName} isn't suitable for current model! "  "** "
		printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
		return 1
	fi
	return 0
}

# Run the Test program
Run() 
{
	if [ "$#" == "0" ] ; then
	cat<<-HELP
	Usage: Run TestItem.ini"
		   eg.: Run SubShell.ini
				SubShell.ini, include sub shell path and file name
				/TestAP/lan/lan_t.sh
	HELP
		exit 4
	fi
	# Usage Run TestItem
	# 此函數將逐一執行SubShell.ini內的指定的shell腳本
	# 多行時則使用${MainDir}/MT/Multithreading.sh多線程執行

	local SubShellList=($(cat ${1} 2>/dev/null | grep -v "#" | grep -v "^$" | awk -F'|' '{print $1}' ))
	case ${#SubShellList[@]} in
		0)	Process 1 "$1 is an empty file ..." && exit 2 ;;
		1)	local FullProgramName=${SubShellList[0]};;
		*)	local FullProgramName=${MainDir}/MT/Multithreading.sh;;
		esac

	# if FullProgramName=${MainDir}/MT/Multithreading.sh, then ProgramName=Multithreading.sh
	local ProgramName=${FullProgramName##*/}

	# Check the proc file exist firstly
	if [ -f "${MainDir}/PPID/${pcb}.proc" ] && [ $(cat -v "${MainDir}/PPID/${pcb}.proc" 2>/dev/null | grep -Ec "^[0-9]") == 0 ]; then
		Process 1 "${MainDir}/PPID/${pcb}.proc is an empty file or no such file ..."
		exit 2
	fi

	# import status checking
	echo "${APVersion}" | grep -iq "l" 
	if [ "$?" == "0" ]; then	
		ChkStatus
		if [ $? == 0 ] ; then
			LockFlag=1
		else
			exit 5
		fi
	fi

	# Run this test item
	CheckVbatAndCmostime ${ProcID} | tee -a "${MainLog}"
	if [ $((ProcID%3)) == 1 ] ; then
		# Check the Error Occurred
		CheckErrorOccurred || exit 1
	fi
	
	# Change the Directory and add test app execute permission 
	chmod 777 ${FullProgramName} >/dev/null 2>&1

	#Check proc file
	if [ -f "${MainDir}/PPID/${pcb}.proc" ] ; then
		cd "${MainDir}/PPID"
		md5sum -c "${MainDir}/PPID/.procMD5" --status >/dev/null 2>&1
		if [ "$?" -ne 0 ]; then
			Process 1 "Check ${MainDir}/PPID/${pcb}.proc" | tee -a "${MainLog}"
			printf "%-10s%-60s\n" "" "Don not modify: ${MainDir}/PPID/${pcb}.proc ..."
			exit 4
		fi
		cd ${MainDir}
	fi

	CheckSizeOfLog "${MainLog}"

	echo "[${ProcID}/${#TotalItemIndex[@]}] ${FullProgramName} start to run in: `date "+%Y-%m-%d %H:%M:%S %z"`" | tee -a "${MainLog}"
	StartTime=$(date +%s.%N)

	while :
	do
		CurFailCnt=$(cat -v "${MainLog}" 2>/dev/null | grep -w "${ProgramName}" | tr -d ' ' | grep  -ic "TestFail")

		# Run the Test item
		[ ! -d "${MainDir}/PPID" ] && mkdir -p "${MainDir}/PPID" 2>/dev/null
		echo "0" > ${MainDir}/PPID/result.tmp
		sync;sync;sync
		
		# For Batch Test
		IgnoreSpecTestItem ${ProgramName} ${TotalItemIndex[$z]}
		if [ $? == 0 ] ; then
			if [ "$(cat -v ${FullProgramName} | grep -ic "ShowTestResultOnScreem")" == 0 ] ; then
				# Not MT Shell exclude "ShowTestResultOnScreem"
				{ 	echo "${FullProgramName##*.}" | grep -iwq "py"
					if [ $? == 0 ] ; then
						python3 ${FullProgramName}
					else
						sh ${FullProgramName} -x ${XmlConfigFile}
					fi
					if [ $? == 0 ] ; then
						echo "0" >  ${MainDir}/PPID/result.tmp
					else
						echo "1" >  ${MainDir}/PPID/result.tmp					
					fi
					sync;sync;sync;
				} 2>&1 | tee -a "${MainLog}" 
			else
				#MT Shell include "ShowTestResultOnScreem"
				{ 
					sh ${FullProgramName} -x ${XmlConfigFile}
					if [ $? == 0 ] ; then
						echo "0" >  ${MainDir}/PPID/result.tmp
					else
						echo "1" >  ${MainDir}/PPID/result.tmp
					fi
					sync;sync;sync;
				}  
			fi 
			sync;sync;sync
		else
			# Save the log in MainLog
			IgnoreSpecTestItem ${ProgramName} ${TotalItemIndex[$z]} 2>&1 | tee -a "${MainLog}"
			echo "Auto to test the next item ..." | tee -a "${MainLog}"
		fi
		
		# test fail
		if [ "$(cat ${MainDir}/PPID/result.tmp 2>/dev/null)"x != "0"x ]; then	
			echo "${FullProgramName} test fail !" | tee -a "${MainLog}" 		
			sync;sync;sync
			# 如果测试项目为以下测试项目，测试一旦fail将直接删除测试资料，并停止测试
			echo "${FullProgramName}" | grep -iwq "lan_c.sh"
				if [ $? == 0 ] ; then
					if [[ $(echo ${APVersion} | grep -ic "u") -ge 1 ]] ; then
						FailLockOrUpload "UPLOAD" | tee -a "${MainLog}"
					fi
					sh ${MainDir}/DelLog/DelLog.sh -x ${XmlConfigFile} 2>/dev/null

				rm -rf ${MainDir}/${BaseName}.ini 2>/dev/null
				exit 1	
				fi
			if [ "${CurFailCnt}" -le "${FailCntLimit}" ]; then
				# 在fail限制的次數內，則show出fail的相關message
				# +-------------------+-----------+-------+----------------------------+
				# |   Test Item       |  ErrCode  | Retry |       Fail message         |
				# +-------------------+-----------+-------+----------------------------+
				# | Multithreading.sh |   TEXFW   |   2   |  Check BIOS version fail   |
				# | ChkBios.sh        |   TEXFW   |   2   |  Check BIOS version fail   |
				# +-------------------+-----------+-------+----------------------------+
				printf "%s\n" "+-------------------+-----------+-------+----------------------------+"
				printf "%-1s%-19s%-1s%-11s%-1s%-7s%-1s%-28s%-1s\n" "|" "   Test Item" "|" "  ErrCode" "|" " Retry" "|" "       Fail message" "|"
				printf "%s\n" "+-------------------+-----------+-------+----------------------------+"
				if [ $(cat ${MainDir}/PPID/ErrorCode.TXT 2>/dev/null | grep -ic "[0-9A-Z]") -ge 1 ] ; then
					for((r=1;r<=`cat ${MainDir}/PPID/ErrorCode.TXT 2>/dev/null | wc -l`;r++))
					do
						printf "%-1s%-19s%-1s"  "|"  " `sed -n ${r}p ${MainDir}/PPID/ErrorCode.TXT | awk -F'|' '{print $3}'`"  "|" 
						printf "%-11s%-1s" "   `sed -n ${r}p ${MainDir}/PPID/ErrorCode.TXT | awk -F'|' '{print $1}'`" "|" 
						printf "%-7s%-1s" "   $((${FailCntLimit}-${CurFailCnt}))" "|" 
						printf "%-28s%-1s\n" "  `sed -n ${r}p ${MainDir}/PPID/ErrorCode.TXT | awk -F'|' '{print $2}'`" "|" 
					done
				else
					printf "%-1s%-19s%-1s%-11s%-1s%-7s%-1s%-28s%-1s\n" "|" " ${FullProgramName##*/}" "|" "    N/A" "|" "   $((4-${CurFailCnt}))" "|" "  ${FullProgramName##*/} test fail" "|"
				fi
				printf "%s\n" "+-------------------+-----------+-------+----------------------------+"				
			else					
				# if fail more than 3 times or not import ng-locking,then delete test logs
				# Fail次數”再次”超過限制的次數后將條碼按Fail上傳，锁定和上传只需选其一即可：即锁定又上传无意义
				if [[ "${CurFailCnt}" -gt "${FailCntLimit}" && $(echo ${APVersion} | grep -ic "u") -ge 1 ]] ; then
					Process 1 "Failure too many time, fail uploading ..."
					FailLockOrUpload "UPLOAD" | tee -a "${MainLog}"
				fi
				
				if [[ "${CurFailCnt}" -gt "${FailCntLimit}" && $(echo ${APVersion} | grep -iv "u" | grep -ic "L") -ge 1 ]] ; then
					Process 1 "Failure too many time, fail locking ..."
					FailLockOrUpload "LOCK" | tee -a "${MainLog}"
				fi
				
				if [ "${CurFailCnt}" -gt "${FailCntLimit}" ] ; then
					#删除 log
					sh ${MainDir}/DelLog/DelLog.sh -x ${XmlConfigFile} 2>/dev/null
                                fi
				#不良次數太多,退出主程式
				rm -rf ${MainDir}/${BaseName}.ini 2>/dev/null
				exit 1

			fi

			# If test fail, press "y" key to run again or "n" key to exit						
			while :
			do
				echo -ne "Run the test again? [ \e[32mY/Enter\e[0m ]=Retest. [ \e[31mN\e[0m ]=Exit."
				read -n 1 answer
				echo ''
				case ${answer:-y} in
				Y|y)
					echo "Operator try to retest: ${FullProgramName}, this the `echo "$CurFailCnt+1" | bc `${Calender[$CurFailCnt]} time..." | tee -a "${MainLog}"
					break;;
					
				N|n)
					rm -rf ${MainDir}/${BaseName}.ini 2>/dev/null
					exit 1;;
				esac
			done	
		else
			# If test Pass. Save ProcID in .proc file
			echo "${FullProgramName} test pass in: `date "+%Y-%m-%d %H:%M:%S %Z"`" 2>&1 | tee -a "${MainLog}"
			echo "${FullProgramName} test pass " >> "${MainLog}"
			rm -rf ${MainDir}/PPID/ErrorCode.TXT 2>/dev/null
			if [ ${ProcID} -gt ${ProcLog} ] ; then
				echo "${ProcID}" > ${MainDir}/PPID/${pcb}.proc
				md5sum ${MainDir}/PPID/${pcb}.proc > ${MainDir}/PPID/.procMD5
				sync;sync;sync
			else
				echo "No found test pass record, and now is retest mode ..."
			fi
			
			ProcID=$((${ProcID}+1))    
			break
		fi
	done

	rm -rf ${MainDir}/PPID/result.tmp 2>/dev/null
	EndTime=$(date +%s.%N)

	# Calculate the Time
	echo "${FullProgramName}" | grep -viwq "nettime.sh\|CmosTime.sh\|SetTime.sh"
	if [ "$?" == 0 ] && [ "${#EndTime}"x != "0"x ]; then
		CostTime=$(printf "%.2f" `echo "scale=2;${EndTime}-${StartTime}+0 " | bc` ) 
		[ "${#CostTime}"x != "0"x ] && echo "Running ${FullProgramName} takes time: ${CostTime} seconds " | tee -a "${MainLog}"
	fi
}
# Run End

TestProcess ()
{
	local maxS=$1
	local curS=$2
	local Sn=$3

	if [ $maxS -gt 40 ] ; then
		maxShow=$(echo ${maxS}/2+1 | bc )
	else
		maxShow=${maxS}
	fi

	let maxShow=${maxShow}+12

	str="${Sn}, "
	arr=("|" "/" "-" "\\") 
	for ((y=0;y<=${curS};y++))
	do  
		let index=y%4   
		let indexcolor=y%8   
		let color=30+indexcolor   
		perc=$(echo "scale=1;$y*100/${maxS}" | bc)
		printf "      Process: [\e[0;32;1m%-${maxShow}s\e[0m][${perc}%%,\e[0;33;1m%d\e[0m/${maxS}]%c\r\e[0m" "$str" "$y" "${arr[$index]}"  
		if [ $maxS -gt 40 ] ; then
			[ $(echo $y%2 | bc ) == 0 ] && str+='>'
		else
			str+='>'
		fi
		sleep 0.01
	done
	printf "\n" 
}

StationCodeMeaning()
{
	local Code=$1
	case $Code in
		1528) echo "Function test";;
		2415) echo "EBT,Burn in test after function test";;
		2597) echo "SCSI,AC OFF/ON,DC OFF/ON";;
		2937) echo "FT2,Function test2";;
		2015) echo "High Voltage test";;
		1543) echo "Pretest";;
		1547) echo "Burn in test";;
		1545) echo "After test";;
		1655) echo "OQA function check";;
		1855) echo "ASSY OQA function check";;
		2515) echo "Pack test";;
		*) echo "No such station code";;
		esac
}

ShowHeader ()
{
	if [ "${BootSN}"x == ""x ] ; then
		# Get the main Disk Label
		BootUUID=$(cat /etc/fstab |grep -iw "uuid" | awk '{print $1}' | sed -n 1p | cut -c 6-100)
		BootLabel=$(blkid | grep -iw "${BootUUID}" | awk '{print $1}' | sed -n 1p | awk '{print $1}' | tr -d ': ')
		BootLabel=$(lsblk | grep -wB30 "`basename ${BootLabel}`" | grep -iw "disk" | tail -n1 | awk '{print $1}')
		BootLabel=$(echo "/dev/${BootLabel}" )
		BootSN=$(hdparm -I ${BootLabel} 2>/dev/null| grep "Serial Number" 2>/dev/null | awk '{print $3}') 
		BootSN=${BootSN:-"No serial number"}
	fi

	CmosDST=$(getCmosDST 2>/dev/null)

	<<-Title
	***************************************************************************
		  Program: 609-S1651-010 Linux Test Program, Internal version: 1.0.0    
	 Main Version: V5.0.0.0                  md5sum: 1acafa61er                
	  Config File: config.xml                md5sum: 6241afecwe 
			  PTE: CodyQin                  Created: 2018/07/02                
			   PE: Jim Green                Updated: 2018/07/03                
		BIOS info: ES165IME.120             Release: 07/31/2013                
		 Firmware: S165K131.ima                                                
		   EERROM: I210I201.bin,I210I101.bin                                   
	  BootHDD S/N: No serial number                                            
		  OS Info: Linux 6.5,2.6.32-431.el6.x86_64                             
		Time Zone: CST,describe:UTC/GMT+0800;DST: 2                            
	 Station Code: 1528,Function test                                          
	***************************************************************************
	Title

	printf "%75s\n" "***************************************************************************"
	printf "%14s%-61s\n" "Program:" " ${ModelName} Linux Test Program, Internal version: ${InternalVersion}"
	printf "%14s%-25s%-8s%-28s\n"  "Main Version:" " ${APVersion}" " md5sum:" " `md5sum ${MainDir}/${BaseName}.sh 2>/dev/null | cut -c 23-32` "
	printf "%14s%-25s%-8s%-28s\n" "Config File:" " ${XmlConfigFile#/$BaseName/}" " md5sum:" " `md5sum ${XmlConfigFile} 2>/dev/null | cut -c 23-32` "
	printf "%14s%-25s%-8s%-28s\n" "PTE:"  " ${PTEName}" "Created:" " `echo $ReleaseDate `" 
	printf "%14s%-25s%-8s%-28s\n" "PE:" " ${PEName}" "Updated:" " `echo ${Update}` "
	printf "%14s%-25s%-8s%-28s\n" "BIOS info:" " ${BiosFile}" "Release:" " `dmidecode -t0 | grep "Release" | head -n1 | awk '{print $NF}'`"
	printf "%14s%-25s%-8s%-28s\n" "Firmware:" " ${BmcFile}"
	printf "%14s%-61s\n" "EERROM:" " ${EepromFile}"
	printf "%14s%-61s\n" "BootHDD S/N:" " ${BootSN}"
	if [ $(uname -r | grep -c '^3.*') -eq 1 ];then
		printf "%14s%-61s\n" "OS Info:" " `cat /etc/redhat-release 2>/dev/null | tr -d '\n' | awk -F' \\\(' '{print $1}' 2>/dev/null`, `uname -r` "
	else
		printf "%14s%-61s\n" "OS Info:" " `cat /etc/issue 2>/dev/null | tr -d '\n' | awk -F' \\\(' '{print $1}' 2>/dev/null`, `uname -r` "
	fi
	printf "%14s%-61s\n" "Time Zone:" " `date +%Z`,  describe: UTC/GMT`date +%z`; CMOS DST: ${CmosDST}"
	printf "%14s%-61s\n" "Station Code:" " ${TestStation}, describe: `StationCodeMeaning ${TestStation}`"
	for iProcess in `ls ${MainDir}/PPID/*.proc 2>/dev/null | grep -iwE '[0-9A-Z]{5}*.proc+$'`
	do
		iProcLog=$(cat ${iProcess} 2>/dev/null | head -n1 )
		SerialNumber=$(echo ${iProcess} | awk -F'/' '{print $NF}' | awk -F'/' '{print $1}' | awk -F'.' '{print $1}' )
		[ ${#iProcLog} != 0 ] && TestProcess ${#TotalItemIndex[@]} ${iProcLog} ${SerialNumber}
	done
	printf "%75s\n" "***************************************************************************"
}

ConfirmStationStatus ()
{
	if [ $(ifconfig -a 2>/dev/null | grep -v "inet" | grep -iPB3 "([\dA-F]{2}:){5}[\dA-F]{2}"| grep -ic "^en\|^eth" ) -gt 0 ] ; then
		ChkStatus || exit 1
	fi
}

CheckAssociatedFiles ()
{
	local AssociatedFiles=(DelLog/DelLog.sh
		ChkLogic/ChkLogic.sh
		Scan/ScanSNs.sh
		GetPrdctInfo/GetMDL.sh
		MT/Multithreading.sh
	)
	for ((f=0;f<${#AssociatedFiles[@]};f++))
	do
		if [ ! -s "${MainDir}/${AssociatedFiles[$f]}" ] ; then
			Process 1 "No such file: ${MainDir}/${AssociatedFiles[$f]}"
			let ErrorFlag++
		fi
	done

	[ ${ErrorFlag} != 0 ] && exit 2
}
#----------------------------------------------------------------------------------------------
#Check status and failure Locking 
GetEthId()
{
	NetcardName=($(ifconfig -a 2>/dev/null | grep -v "inet" | grep -iPB3 "([\dA-F]{2}:){5}[\dA-F]{2}" | grep -iE "^e[nt]" | awk '{print $1}' | tr -d ':'))

	if [ ${#NetcardName[@]} == 0 ] ; then
		Process 1 "No found any LAN devices ..."
		exit 2
	fi

	printf "%-7s%-23s%-26s%-10s\n" " No" "Ethernet" "MAC Address" "Link Status"
	echo "----------------------------------------------------------------------"
	for ((e=0;e<${#NetcardName[@]};e++))
	do
		# No    Ethernet               MAC Address               Link Status
		#---------------------------------------------------------------------- 
		# 01  	eth0                   123456789012                  YES
		# 02  	eth1                   123456789013                  NO
		# 03  	enp0s2f3               12345678901A                  NO
		#----------------------------------------------------------------------	
				
		# Get MAC address and Get Link status
		MacAddr[$e]=$(ifconfig ${NetcardName[$e]} 2>/dev/null | sed 's/ /\n/g' | grep -iP "([\dA-F]{2}:){5}[\dA-F]{2}" | tr -d ':' | tr '[a-z]' '[A-Z]')
		LinkStatus[$e]=$(ethtool ${NetcardName[$e]} 2>/dev/null | grep -i "Link detected" | awk -F':' '{print $2}' | tr -d ' ' | tr [a-z] [A-Z])
		
		if [ $(echo ${LinkStatus[$e]} | grep -ic "YES") -gt 0 ]  ; then
			printf "\e[1;32m%-1s%02d%-04s%-23s%-30s%-10s\n\e[0m" " " "$((e+1))" "" "${NetcardName[$e]}" "${MacAddr[$e]}" "${LinkStatus[$e]}"
			let PortIndex=$e
		else
			printf "%-1s%02d%-04s%-23s%-30s%-10s\n" " " "$((e+1))" "" "${NetcardName[$e]}" "${MacAddr[$e]}" "${LinkStatus[$e]}"
		fi
		
	done
	echo "----------------------------------------------------------------------"
	echo
}

PingServerTest () 
{
	local IPAddress=$(echo ${NgLockWebSite} | awk -F'/' '{print $3}')
	local RunCycle=3
	IPAddress=${IPAddress:-"20.40.1.41"}
	while :
	do
		GetEthId
		
		ifconfig ${NetcardName[$PortIndex]} 2>/dev/null
		ethtool ${NetcardName[$PortIndex]} 2>/dev/null | grep -i "Link detected" | grep -iwq 'yes' 
		if [ $? == 0 ] ; then
			ping ${IPAddress} -I ${NetcardName[$PortIndex]} -c 3 2>/dev/null
			Process $? "Ping ${IPAddress} from LAN(${MacAddr[$PortIndex]}) ..." && break
		fi
		
		for ((e=0;e<${#NetcardName[@]};e++))
		do
			# ping fail 
			ifconfig ${NetcardName[$e]} down >/dev/null 2>&1
			dhclient -r ${NetcardName[$e]}   >/dev/null 2>&1
			sleep 1
			ifconfig ${NetcardName[$e]}      >/dev/null 2>&1
		done
		
		for ((;RunCycle>0;RunCycle--))
		do
			dhclient -r >/dev/null 2>&1
			printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
			printf "\e[0;30;43m%-6s%-60s%6s\e[0m\n" " **"  "Please plug net cable in: ${NetcardName[$PortIndex]}, ${MacAddr[$PortIndex]}"  "** "
			printf "\e[0;30;43m%-6s%-60s%6s\e[0m\n" " **"  "Wait some seconds, press Enter to continue.."  "** "
			printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
			WaitPlugInLanCable 9
			dhclient -timeout 10
			ping ${IPAddress} -I ${NetcardName[$PortIndex]} -c 2
			Process $? "Ping ${IPAddress} from LAN(${MacAddr[$PortIndex]}) "
			if [ "$?" == "0" ];then
				break 2
			else
				[ ${RunCycle} == 1 ] && exit 1
				continue 2
			fi       	
		done
		break
	done
}

WaitPlugInLanCable ()
{
	local CycleTime=$1
	for ((p=${CycleTime:-15};p>0;p--))
	do   
		printf "\rPlug in lan cable, press \e[1;33m[Y/y]\e[0m key, time remaining: %02d seconds ..." "${p}"
		read -s -t 1 -n1 Ans
		case ${Ans:-h} in
		Y|y) echo &&  break;;
		Q)
			trap '-' INT QUIT TSTP HUP 
			echo
			echo -e "\e[1;33mPress [Ctrl]+[C] to exit ...\e[0m"
			read -t 20
			trap '' INT QUIT TSTP HUP 
		 ;;
		 
		 *) : ;;
		esac
	done
	echo ''
} 

Wait4nSeconds ()
{
	local CycleTime=$1
	for ((p=${CycleTime:-15};p>0;p--))
	do   
		if [ ${CycleTime} -le 30 ] ; then
			printf "\rPress \e[1;33m[y]\e[0m key to continue, \e[1;33m[q]\e[0m to quit, after %02d seconds auto continue ..." "${p}"
			read -s -t 1 -n1 Ans
		else
			if [ ${p} == ${CycleTime} ] ; then
				printf "Press \e[1;33m[Y/y]\e[0m key to continue, \e[1;33m[q/Q]\e[0m to quit ...\n"
				printf "$((${p}/60)) min remaining"
			fi
			
			printf "."
			if [ $((${p}%60)) == 0 ] ; then
				printf "\r                                                                                \r$((${p}/60-1)) min remaining"
			fi
			
			read -s -t 0.9 -n1 Ans
		fi
		
		case ${Ans:-h} in
		Y|y) echo && break;;
		Q|q) echo && return 1 ;;
		 *) : ;;
		esac
	done
	echo ''
	return 0
} 

ChkStatus()
{
	ChkExternalCommands w3m jq

	NgLockWebSite=${NgLockWebSite:-"http://20.40.1.40/EPS-Web/TestFail/GetInfo.ashx"}
	if [ ${#pcb} != 0 ] ; then
		local CurProcLOG=$(cat ${MainDir}/PPID/${pcb}.proc 2>/dev/null )
		let CurProcLOG=${CurProcLOG}+1 
		IndexSet=($(xmlstarlet sel -t -v  "//Programs/Item/@index" ${XmlConfigFile} 2>/dev/null | sort -nu))
		xmlstarlet sel -t -v  //Programs/Item[@index=${IndexSet[CurProcLOG-1]}] ${XmlConfigFile} 2>/dev/null | grep -iq "Net\|Cmos\|PingServer\|BMC\|lan\|ip\|ncsi\|shutdown\|reboot\|finish\|Multithreading\|getModel\|compareDT" && return 0
	fi

	NetcardName=($(ifconfig -a 2>/dev/null | grep -v "inet" | grep -iPB3 "([\dA-F]{2}:){5}[\dA-F]{2}" | grep -iE "^e[nt]" | awk '{print $1}' | tr -d ':'))
	if [ ${#NetcardName[@]} == 0 ] ; then
		printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
		printf "\e[0;30;43m%-6s%-60s%6s\e[0m\n" " **"  "No Ethernet device/MAC Address found"  "** "
		printf "\e[0;30;43m%-72s\e[0m\n" " ********************************************************************** "
		return 0
	fi

	PingServerTest

	# 0,is still in the WareHouse,if debug ,does not remove the letter "L" from TPVer in TestAP.sh
	case ${StationCode} in
		1528) StationCode="1528,2695,0";;
		*) StationCode=$(echo "${StationCode},0");;
		esac

	# if LockFlag=0, check it	
	LockFlag=${LockFlag:-0}	
	until [ "${LockFlag}"x != "0"x ]
	do
		echo -e "\e[33m Begin to verify station status, please wait a moment ...\e[0m"
		echo
		
		# Serial Number  Station  ErrCode  Status   Failure Message     Result
		#----------------------------------------------------------------------
		#  I316788015     2695     TXLEA    Lock    LAN                  Fail
		#  I316788016     1855     TXLEB    ---     ---                  Pass
		#----------------------------------------------------------------------
		printf "%-16s%-9s%-9s%-9s%-20s%-7s\n" "Serial Number"  "Station" "ErrCode"  "Status"   "Failure Message" "Result"
		echo "----------------------------------------------------------------------"
		SNs=($(cat -v ${MainDir}/PPID/SN_MODEL_TABLE.TXT "${MainDir}/PPID/PPID.TXT" 2>/dev/null | awk -F'|' '{print $1}' |  sort -u ))
		for ((s=0;s<${#SNs[@]};s++))
		do
			#'{"status":"Lock","NextStation":"2675","Msg":{"Info":"LED","Code":"TXB68"}}'
			local StatusLog=${SNs[$s]}_Status.log
			rm -rf ${StatusLog} 2>/dev/null
			w3m "${NgLockWebSite}?opt=GS&sBarcode=${SNs[$s]}"  2>&1 | tr -d "'" >> ${StatusLog}
			sync;sync;sync 
			local Status=$(jq ".status" ${StatusLog} 2>/dev/null | tr -d '"' )
			
			local NextStation=$(jq ".NextStation" ${StatusLog} 2>/dev/null | tr -d '"' )
			NextStation=${NextStation:-"----"}
			
			local Errcode=$(jq ".Msg.Code" ${StatusLog} 2>/dev/null | tr -d '"' )
			local FailMsg=$(jq ".Msg.Info" ${StatusLog} 2>/dev/null | tr -d '"' )
			
			printf "%-17s%-9s%-9s%-8s%-21s" "${SNs[$s]}" "${NextStation:0:4}" "${Errcode:-"-----"}" "${Status:-"----"}" "${FailMsg:-"----"}" 
			
			if [ "${Status}"x == "Lock"x ] || [ "${NextStion}x" == "----x" ] || [ $(echo "${StationCode}" | grep -iw "${NextStion}" ) != 0 ]; then
				printf "\e[31m%-6s\n\e[0m" "Fail"
				let ErrorFlag++
			else
				printf "\e[32m%-6s\n\e[0m" "Pass"
			fi	
		done
		echo "----------------------------------------------------------------------"
		LockFlag=1
	done
	[ ${ErrorFlag} != 0 ] && exit 1
	return 0
}
#----------------------------------------------------------------------------------------------
# Fail locking and upload
Connet2Server ()
{
	local IPAddress=$1
	while :
	do
		ping ${IPAddress} -c 2 -w 3 2>/dev/null 
		if [ "$?" != "0" ] ; then 
			dhclient -r
			echo -e "\033[0;30;44m ********************************************************************** \033[0m"
			echo -e "\033[0;30;44m ***       Plug LAN cable in a LAN port to connect the server       *** \033[0m"
			echo -e "\033[0;30;44m ********************************************************************** \033[0m"  
			WaitPlugInLanCable 6 
			dhclient -timeout 5			
		else
			break
		fi
	done
}

MountLogFTP ()
{
	local LogFTPIp=$1
	for ((cnt=0;cnt<3;cnt++))
	do
		#Mount the Log Server to /mnt/logs
		mkdir -p /mnt/logs
		mount -t cifs //${LogFTPIp}/Testlog/SI/ -o rw,username=test,password=test,vers=1.0  /mnt/logs/
		if [ "$?" == "0" ]; then
			Process 0 "Mount //${LogFTPIp}/Testlog/SI/"
			echo "Please wait a moment ..." 
			break
		else
			Process 1 "Try again, please wait a moment..."
			umount /mnt/logs/ >/dev/null 2>&1
			sleep 1
		fi
	done

	[ ${cnt} -ge 3 ] && exit 1
	return 0
}

# Backup Test Log Function
BackupTestLog ()
{
	local sn=$1
	local folder=$2
	local LogFTPIp=$3
	local BackupLogPath=/mnt/logs
	echo "${folder}" | grep -q '-'
	if [ $? == 0 ]; then
		folder=$(echo "${folder}" | awk -F'-' '{print $2}')
	fi
	folder=${folder:-"96D9"}
	case ${TestStation} in
		1528)FLAG="FT";;
		2415)FLAG="EBT";;
		2597)FLAG="SCSI";;
		2937)FLAG="FT2";;
		1543)FLAG="PF";;
		1547)FLAG="BiT";;
		1545)FLAG="AF";;
		1655)FLAG="OQA";;
		1855)FLAG="OQA";;
		2515)FLAG="PT";;
		*)FLAG="Unkown";;
		esac

	echo -e " Back up test Log ... "
	# if pcb='', then get the value from PPID.TXT
	pcb=${pcb:-"`cat -v ${MainDir}/PPID/PPID.TXT`"}

	# e.g.:backup_log_name=FT_2017022018080808_H216263168.log
	local CurYearMonth=$(date +%Y%m)
	local LogFileName=${FLAG}_FAIL_$(date "+%Y%m%d%H%M%S")_${sn}.log
	echo -e "\n This log file save in: //${LogFTPIp}/Testlog/SI/${folder}/${CurYearMonth} " >> ${MainDir}/PPID/${pcb}.log
	sync;sync;sync

	#If the folder not found,then make it
	[ ! -d "${BackupLogPath}/${folder}/${CurYearMonth}" ] && mkdir -p  ${BackupLogPath}/${folder}/${CurYearMonth} 2>/dev/null

	#Copy local log to FTP server
	cp -rf ${MainDir}/PPID/${pcb}.log ${BackupLogPath}/${folder}/${CurYearMonth}/${LogFileName} 2>/dev/null
	Process $? "Back up test log of ${sn} to /mnt/logs/${folder}" || return 1
	return 0
}
# Create Test XML Function
CreateXML()
{	
	local sn=$1
	local KEY_WORD=($(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/Components/KeyWord" -n ${XmlConfigFile} 2>/dev/null))
	local FILE_LIST=($(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/Pretest/FailLockAndUpload/Components/FileList" -n ${XmlConfigFile} 2>/dev/null))

	echo " Creating test XML... "
	XML_TEXT="<root>"

	# Write Test station 
	XML_TEXT=${XML_TEXT}"<TestStation>${TestStation}</TestStation>"

	# Write Test Machine
	read text < ${MainDir}/PPID/FIXID.TXT
	if [ "${#text}" == 0 ] ; then
		Process 1 "Error: Read fixid failure ..."
		return 1
	else
		XML_TEXT=${XML_TEXT}"<TestMachine>$text</TestMachine>"
	fi
	

	# Write Test OP ID
	read text < ${MainDir}/PPID/OPID.TXT
	if [ "${#text}" == 0 ] ; then
		Process 1 "Error: Read OperID failure ..."
		return 1
	else
		XML_TEXT=${XML_TEXT}"<Tester>$text</Tester>"
	fi

	# Write Test Barcode,# read text < $PATH_DATA$FILE_PPID
	text=${sn} 
	if [ "${#text}" == 0 ] ; then
		Process 1 "Error: Read PPID failure ..."
		return 1
	else
		XML_TEXT=${XML_TEXT}"<BarcodeNo>$text</BarcodeNo>"
	fi
	

	# Write Test Status,F,for failure case
	TEST_STATUS='F'
	XML_TEXT=${XML_TEXT}"<TestStatus>$TEST_STATUS</TestStatus>"

	# Write Customer
	XML_TEXT=${XML_TEXT}"<Customer></Customer>"

	# Write Test Time
	XML_TEXT=${XML_TEXT}"<TestTime>"$(date "+%Y-%m-%d %H:%M:%S")"</TestTime>"	

	# Write Test Info
	XML_TEXT=${XML_TEXT}"<TestInfo>"
	for ((i=0;i<${#KEY_WORD[@]};i++))
	do
		read text < ${MainDir}/PPID/${FILE_LIST[$i]}
		if [ ${#text} == 0 ] ;then
			Process 1 "Error: Read ${KEY_WORD[$i]} failure ..."
			return 1
		fi

		XML_TEXT=${XML_TEXT}"<TestItem Key=\"${KEY_WORD[$i]}\">$text</TestItem>"
	done

	XML_TEXT=${XML_TEXT}"</TestInfo>"

	# Write Ng Info
	XML_TEXT=${XML_TEXT}"<NgInfo>"
	XML_TEXT=${XML_TEXT}"<Errcode>${ERROR_CODE}</Errcode>"
	XML_TEXT=${XML_TEXT}"<Pin></Pin><Local></Local>"
	XML_TEXT=${XML_TEXT}"</NgInfo>"
	XML_TEXT=${XML_TEXT}"</root>"
	echo ${XML_TEXT} | xmlstarlet fo
	Process $? "Create Test XML of ${sn} ..." || return 1
	return 0
}
# Create Test XML End
Backuplog2Local ()
{
	local Model=$1
	local sn=$2
	Model=${Model:-"SI_Moedl"}
	# Usage: Backuplog2Local Model SN
	#Back up Test log to local disk
	echo "${Model}" | grep -q '-'
	if [ $? == 0 ]; then
		Model=$(echo "${Model}" | awk -F'-' '{print $2}')
	fi

	local Name=$(echo "$(date "+%Y%m%d%H%M%S")_${sn}")
	mkdir -p  /."${Model}"/${Name} > /dev/null 2>&1
	cp -rf ${WorkPath}/${pcb}.log   /."${Model}"/${Name}/         > /dev/null 2>&1
	cp -rf ${WorkPath}/${pcb}.proc  /."${Model}"/${Name}/         > /dev/null 2>&1
	cp -rf ${WorkPath}/.procMD5     /."${Model}"/${Name}/procMD5  > /dev/null 2>&1
	for iFILE in ${FILE_LIST[@]}
	do
		cp -rf ${WorkPath}/${iFILE} /."${Model}"/${Name}/ > /dev/null 2>&1
	done

	cd /."${Model}"/ 2>/dev/null
	tar -zcvf ${Name}.tar.gz ${Name}/ >/dev/null 2>&1 
	rm -rf ${Name}/ 2>/dev/null
	cd ${WorkPath} 2>/dev/null
}

FailLockOrUpload ()
{
	ChkExternalCommands w3m jq mes
	#function: Lock or Upload
	local function=$(echo "$1" | tr "[a-z]" "[A-Z]")
	local IPAddress=${IPAddress:-"20.40.1.41"}
	local pcb=$(cat -v ${MainDir}/PPID/PPID.TXT | head -n1 )
	echo -e "\033[1;33m Lock test fail result to the database ... \033[0m"
	cat -v "${ErrorCodeFile}" 2>/dev/null | head -n1 | tr '|' ',' > ${MainDir}/PPID/FAILITEM.TXT

	# Step 2
	# Auto link server,network_segment=172(172.17.x.x),or 20(20.40.x.x) and mount the FTP to /mnt/logs
	Connet2Server ${IPAddress}
	MountLogFTP ${IPAddress} 2>/dev/null

	FailTotalItems=$(cat -v "${ErrorCodeFile}" | grep -iEc '[0-9A-Z]')
	if [ ${FailTotalItems} != 0 ] ; then
		if [ ${function} == "LOCK" ] ; then
			echo "Fail 鎖定程式 ..."
			echo "Backup the test log and locking ..."
			printf "%-15s%-12s%-12s%-19s%-8s%-6s\n"  "SerialNumber" "ModelName" "ErrCode" "Fail Item" "Bk-Log"  "Locked"
			
		else
			echo "Fail 上傳程式 ..."
			echo "Backup the test log and upload ..."
			printf "%-15s%-12s%-12s%-19s%-8s%-8s\n"  "SerialNumber" "ModelName" "ErrCode" "Fail Item" "Bk-Log"  "Upload"		
		
		fi
		echo "------------------------------------------------------------------------"
	fi
	for((e=1;e<=${FailTotalItems};e++))
	do

		local Record=$(sed -n ${e}p ${ErrorCodeFile})
		local ErrorItem=$(echo ${Record} | awk -F'|' '{print $3}')
		local ERROR_CODE=`echo "${Record}" | awk -F'|' '{print $1}'`	
		local ErrorModel=($(xmlstarlet sel -t -v "//Programs/Item" -n "${XmlConfigFile}" | grep -w "${ErrorItem}" | tr "|" "\n" | grep -v "${ErrorItem}" ))
		if [ ${#ErrorModel} == 0 ] ; then
			SerialNumber=($(cat ${MainDir}/PPID/SN_MODEL_TABLE.TXT | awk -F'|' '{print $1}'))
			ErrorModel=($(cat ${MainDir}/PPID/SN_MODEL_TABLE.TXT | awk -F'|' '{print $2}'))
		else
			SoleErrorModel=$(echo ${ErrorModel[@]} | sed 's/ /\\|/g')
			SerialNumber=($(cat ${MainDir}/PPID/SN_MODEL_TABLE.TXT | grep -w "${SoleErrorModel}" | awk -F'|' '{print $1}'))
		fi

		# SerialNumber  ModelName   ErrCode   Fail Item         Bk-Log   Locked/Upload   
		#------------------------------------------------------------------------
		# H123456789    S1561 		 TXW7Z      ChkBios.sh       Pass     Pass      
		# H123456789    S1561 		 TXW7Z      ChkBios.sh       Pass     Pass            
		# H123456789    S1561 		 TXW7Z      ChkBios.sh       Pass     Fail            
		# H123456789    S1561 		 TXW7Z      ChkBios.sh       Fail     ----     
		#------------------------------------------------------------------------
		for ((s=0;s<${#SerialNumber[@]};s++))
		do
			printf "%-15s%-12s%-12s%-20s" " ${SerialNumber[$s]}" " ${ErrorModel[$s]}" " ${ERROR_CODE}" "${ErrorItem}"
			BackupTestLog "${SerialNumber[$s]}" "${ErrorModel[$s]}" ${IPAddress} 1>/dev/null
			if [ $? -ne 0 ] ; then
				let ErrorFlag++
				printf "%-8s" "Fail"
			else
				printf "%-8s" "Pass"
			fi
			
			# Back up Test log to local disk
			Backuplog2Local "${ErrorModel[$s]}" "${SerialNumber[$s]}" ${IpAddress} 1>/dev/null
			# for FAIL lock and upload
			echo ${Record} | tr '|' ',' > ${MainDir}/PPID/FAILITEM.TXT
			sync;sync;sync
				
			# Create Test XML 
			CreateXML "${SerialNumber[$s]}" >/dev/null
			if [ $? -ne 0 ] ; then
				let ErrorFlag++
				continue
			fi
			
			case ${StationCode} in
			1528) StationCode="1528,2695,0";;
			*) StationCode=$(echo "${StationCode},0");;
			esac
			
			# Lock，單項執行此程式的時候FailLocking沒有從TestAP.sh傳過來，因此執行鎖定
			echo "${FailLocking:-'enable'}" | grep -iwq "enable"
			if [ $? == 0 ] && [ "${function}" == "LOCK" ] ; then
				rm -rf .LockingResult.log 2>/dev/null
				w3m "${NgLockWebSite}?opt=TF&sXML=${XML_TEXT}" 2>&1| tr -d "'" > .LockingResult.log
				w3m "${NgLockWebSite}?opt=GS&sBarcode=${SerialNumber[$s]}"  2>&1 | tr -d "'" >> .LockingResult.log
				sync;sync;sync
				cat -v .LockingResult.log 2>/dev/null| grep -iq 'lock'
				if [ $? -ne 0 ] ; then
					[ ${function} == "LOCK" ] && printf "%-6s" "Fail"
				else
					[ ${function} == "LOCK" ] && printf "%-6s" "Pass"
					let ErrorFlag++
					cat ${MainDir}/PPID/FailureTestResult.txt 2>/dev/null | grep -wq "${SerialNumber[$s]}|${ErrorModel[$s]}|Fail|${ERROR_CODE}"
					if [ $? != 0 ] ; then
						echo "${SerialNumber[$s]}|${ErrorModel[$s]}|Fail|${ERROR_CODE}" >> ${MainDir}/PPID/FailureTestResult.txt
						sync;sync;sync
					fi
				fi
			else
				[ ${function} == "LOCK" ] && printf "%-6s" "Skip"
				cat ${MainDir}/PPID/FailureTestResult.txt 2>/dev/null | grep -wq "${SerialNumber[$s]}|${ErrorModel[$s]}|Fail|${ERROR_CODE}"
				if [ $? != 0 ] ; then
					echo "${SerialNumber[$s]}|${ErrorModel[$s]}|Fail|${ERROR_CODE}" >> ${MainDir}/PPID/FailureTestResult.txt
					sync;sync;sync
				fi				
			fi
			
			echo "${FailUpload:-'enable'}" | grep -iwq "enable"
			if [ $? == 0 ] && [ "${function}" == "UPLOAD" ]  ; then
				rm -rf .UploadMesResult.log 2>/dev/null
				mes "${MesWebSite}" 1 "sXML=${XML_TEXT}" > .UploadMesResult.log 2>&1
				cat -v .UploadMesResult.log | grep -iq "[0-9A-Z]"
				if [ $? -ne 0 ] ;then
					[ ${function} == "LOCK" ] || printf "\e[31m%-6s\e[0m\n"  "NULL"
					let ErrorFlag++
				else
					local UploadMesResult=$(cat -v .UploadMesResult.log | grep -v "=" | head -n1 | tr -d "^M")
					if [ $(echo ${UploadMesResult} | grep -ic "OK\|Warehouse") -ge "1" ] ; then
						[ ${function} == "LOCK" ] || printf "\e[32m%-6s\e[0m\n" "PASS"
						let ErrorFlag++
					else
						[ ${function} == "LOCK" ] || printf "\e[31m%-6s\e[0m\n" "FAIL"
					fi			
				fi
			else
				[ ${function} == "LOCK" ] || printf "%-6s\n" "Skip"
			fi
		done

	done
	[ ${FailTotalItems} != 0 ] && echo "------------------------------------------------------------------------"
	umount -a >/dev/null 2>&1
	[ ${ErrorFlag} -ne 0 ] && return 1
	return 0
}
#----------------------------------------------------------------------------------------------
# Encrypt
CalculateMD5()
{
	ChkExternalCommands "whiptail"
	local AllShell=()
	ShowTitle "Calculate and verify for Linux shell"
	while :
	do
		#read -p "Please input a password: " -s psw
		local psw=$(whiptail --title "Enter Password" --passwordbox "Enter the password to calculate the md5sum of programs and choose OK to continue." 10 60 3>&1 1>&2 2>&3)
		echo -n ${psw}  | md5sum | grep -iwq "${EncryptPassword}"
		if [ $? == 0  ]; then
			cp -rf ${StdMD5} ${Md5Path}/OriginalStdMD5 2>/dev/null
			echo
			# type-1 
			#AllShell=($(find ${MainDir}/ -type f -maxdepth 2 2>/dev/null | grep -iE "[xmlsh]{2,3}+$" | grep -iEv 'lan[0-9]{1,3}_' | grep -iv 'run' | grep -iv ' ' | tr '\n' ' '))
			
			# type-2
			AllShell=($(xmlstarlet sel -t -v "//Programs/Item" -n "${XmlConfigFile}" 2>/dev/null | awk -F'|' '{print $1}' |  tr '\n' ' '))
			AllShell=($(echo "${AllShell[@]} ${MainDir}/${BaseName}.sh"))
			local OtherPath=(ChkLogic GetPrdctInfo MT DelLog Scan Config)
			for ((p=0;p<${#OtherPath[@]};p++))
			do
				AllShell=(${AllShell[@]} `find ${MainDir}/${OtherPath[$p]} -type f -maxdepth 2 2>/dev/null | grep -iE "[xmlsh]{2,3}+$"`)
			done
			AllShell=($(echo ${AllShell[@]} | tr ' ' '\n' | sort -u ))
			for((a=0;a<${#AllShell[@]};a++))
			do
				if [ ! -f "${AllShell[$a]}" ] ; then
					Process 1 "No such file: ${AllShell[$a]}"
					let ErrorFlag++
				fi
			done
			[ ${ErrorFlag} -ne 0 ] && exit 1
			# end type-2
			
			md5sum ${AllShell[@]} | tee ${StdMD5}
			if [ -s ${StdMD5} ] ; then
				local ShellCnt=$(echo ${AllShell[@]} | tr ' ' '\n' | grep  -iEc "sh+$")
				local XMLCnt=$(echo ${AllShell[@]} | tr ' ' '\n' | grep  -iEc "xml+$")	
				Process 0 "Shell files: $ShellCnt, XML files: $XMLCnt, have been encrypt"
				break
			fi
		else
			whiptail --title "Invalid password" --msgbox "Invalid password, please try again." 10 60
		fi
	done 
	return 0
}

CheckMD5()
{
	ChkExternalCommands "md5sum" "stat"
	# Get a unique name
	local ShellList=($(xmlstarlet sel -t -v "//Programs/Item" ${XmlConfigFile} 2>/dev/null | tr -d '\t ' | grep -v "^$" | awk -F'|' '{print $1}' ))
	local SoleShellList=($(echo ${ShellList[@]} | tr ' ' '\n' | sort -u ))
	local SoleShellList=$(echo ${SoleShellList[@]} | sed 's/ /\\|/g')

	if [ -s "${StdMD5}" ] ; then
		local FailList=($(md5sum -c ${StdMD5} 2>/dev/null | grep -iv "OK" | awk -F':' '{print $1}' ))
		local PassList=($(md5sum -c ${StdMD5} 2>/dev/null | grep -i "OK" | awk -F':' '{print $1}' | grep "${SoleShellList}\|${BaseName}.sh" ))
		md5sum -c ${StdMD5} 2>&1 | grep -iwq "NOT MATCH"
		if [ $? != 0 ] && [ ${#PassList[@]} -ge ${#ShellList[@]} ] ; then
			return 0
		fi
		[ ${#FailList[@]} == 0 ]  && return 0
 	fi
	
	ShowTitle "MD5 verify tool for Linux Shell"
	printf "%-29s%-10s%-10s%-19s\n"  "   Program" "Ori. MD5" "Cur. MD5" "   Modify Time"
	echo "----------------------------------------------------------------------"
	for((f=0;f<${#FailList[@]};f++))
	do
		# Cut the 25-32bit
		OriMD5SUM=$(cat -v ${StdMD5} 2>/dev/null | grep -w "${FailList[$f]}" | awk '{print $1}' | cut -c 25- )
		CurMD5SUM=$(md5sum "${FailList[$f]}" 2>/dev/null | awk '{print $1}' | cut -c 25- )
		ModifyTime=$(stat "${FailList[$f]}" 2>/dev/null | grep -iw "modify" | awk -F'fy:' '{print $2}' | awk -F'.' '{print $1}' )
		#    Program                   Ori. MD5   Cur. MD5      Modify Time
		# ----------------------------------------------------------------------
		# /TestAP/TestAP.sh            95a32a0f   95a32a0f   2018-07-08 14:12:32
		# /TestAP/Scan/ScanOPID.sh     95a32a0f   95a32a0f   2018-07-08 14:12:32
		# /TestAP/Scan/ScanFixID.sh    95a32a0f   95a32a0f   2018-07-08 14:12:32	
		# /TestAP/ChkBios/ChkBios.sh   95a32a0f   95a32a0f   2018-07-08 14:12:32	
		# ----------------------------------------------------------------------
		PrintFailList=$(echo ${FailList[$f]} | awk -F'/' -v p='/' '{print $(NF-1) p $NF}')
		printf "%-29s%-10s%-10s%-19s\n"  "${PrintFailList}" "${OriMD5SUM}" "${CurMD5SUM:-"--------"}" "${ModifyTime:-" No such file"}"

	done
	echo "----------------------------------------------------------------------"
	Process 1 "Do not modify any program. MD5 verify ..."
	return 1
}

EncryptTestProgram ()
{
	if [ "$(echo ${APVersion} | grep -ic "S" 2> /dev/null)"x != "0"x ] ; then
		while :
		do
			#Encrypt the Test program; If APVersion include the letter "S" mean this test program is encrypted
			CheckMD5
			if [ $? == 0 ] ;then
				break
			else
				read -t 5
				CalculateMD5
				continue				
			fi
		done
	fi
	return 0
}

CheckParameter ()
{
	#檢查配置檔是否都有配置信息, 2020/09/07
	local ItemList=($(xmlstarlet sel -t -v  "//Programs/Item" ${XmlConfigFile} 2>/dev/null | awk -F'|' '{print $1}'))
	for((v=0;v<${#ItemList[@]};v++))
	do
		xmlstarlet sel -t -v "//TestCase/ProgramName" ${XmlConfigFile} 2>/dev/null | grep -wq "`basename ${ItemList[v]} .sh`"
		if [ $? != 0 ]; then
			Process 1 "No config of ${ItemList[v]} found in ${XmlConfigFile} ."
			let ErrorFlag++
		fi
	done
	[ ${ErrorFlag} != 0 ] && exit 1 
	return 0
}

#----------------------------------------------------------------------------------------------
# Check Error Occurred
CheckErrorOccurred ()
{
	ChkExternalCommands "dmesg"
	local ErrorOccurredFlag='0'
	local ErrorOccurredList='ErrorOccurredList'
	local CheckListCnt=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ErrorsOccurredType/Item" -n "${XmlConfigFile}" 2>/dev/null | grep -v "#" | grep -v "^$" |  wc -l)
	for ((e=1;e<=${CheckListCnt};e++))
	do
		local CheckList=$(xmlstarlet sel -t -v "//MainProg[ProgramName=\"${BaseName}\"]/ErrorsOccurredType/Item[$e]" -n "${XmlConfigFile}" 2>/dev/null | grep -v "#" | grep -v "^$" | grep -iE '[0-9A-Z]')
		local Amount=$(dmesg | grep -ic "${CheckList}")
		if [ ${Amount} != 0 ] ; then
			echo ${ErrorsOccurredChk} | grep -iwq "disable" 
			if [ $? == 0 ] ; then	
				printf "%-1s\e[1;33m%-7s\e[0m%-2s%-60s\n" "[" "Warning" "] " "Found \"${CheckList}\" occurred ${Amount} time(s) in total ..."
			else
				Process 1 "Found \"${CheckList}\" occurred ${Amount} time(s) in total ..."
			fi
			ErrorOccurredList=$(echo ${ErrorOccurredList}\|${CheckList})
			let ErrorOccurredFlag++
		fi
	done
	if [ ${ErrorOccurredFlag} != 0 ] ; then
		echo "======================================================================" | tee -a "${MainLog}"
		printf "\e[1;33m%s\e[0m\n" "Error occurred detail: "						  | tee -a "${MainLog}"
		dmesg -T | grep -iwE "${ErrorOccurredList}"					  				  | tee -a "${MainLog}"
		echo "======================================================================" | tee -a "${MainLog}"
		echo ${ChkErrorsOccurred} | grep -iwq "disable" 
		if [ $? != 0 ] ; then
			let ErrorFlag++
			return 1
		fi
	fi
	return 0
}
#----Main function-----------------------------------------------------------------------------
# Begin the program
#Change the directory
declare MainDir=$(cd `dirname $0`; pwd)
declare UtilityPath=$(cd `dirname $0`; cd ${MainDir}/utility 2>/dev/null; pwd)
cd ${MainDir} >/dev/null 2>&1 
declare PATH=${PATH}:${UtilityPath}:`pwd`
export PYTHONPATH="$PYTHONPATH:/TestAP/bin:/TestAP/utility"

# Define the arguments
# Set the terminal as English
LANG=en_US.UTF-8
declare Calender=(st nd rd th th th th th th th th th th th th th th th th th th th)
declare -i ErrorFlag=0

#--->Get and process the parameters
export XmlConfigFile=($(ls ${MainDir}/Config/*.xml))
if [ ${#XmlConfigFile[@]} != 1 ] ; then
	Process 1 "Too much or no found XML config file. Check XML"
	ls ${MainDir}/Config/*.xml
	exit 3
fi

ChkExternalCommands

#XmlConfigFile: XML config file
#     PTEName: Name of PTE
#      PEName: Name of PE
# ReleaseDate: The release date of the program, for PTE only
#      Update: The update date of the program, for PE only
#      BootSN: The serial number of BOOT disk
#     MainLog: ${MainDir}/PPID/$pcb.log
#   ModelName: The name of model,eg.: 609-S1651-04S
#    BiosFile: The name of BIOS file,eg.: ES165IME.160
#     BmcFile: The name of BMC FW file,eg.: ES165K135.ima
#  EepromFile: The name of EEPROM FW file,eg.: II210201.bin, I354301.eep
#       MpsFW: The FirmWare file of MPS, eg.: config.csv
#   APVersion: The version of program
# FailLocking: If test fail more than 5 times ,then lock the M/B
#     Encrypt: Encrypt the program:  enable or disable
#     ProcLog: Process ID of log
#      ProcID: Process ID of Current
#        Path: Path of the shell
#         pcb: Current PCB serial which get from the scanner
# TestStation: Current Test Station
declare InternalVersion=V1.2.0
declare BaseName=$(basename $0 .sh)
declare CurBiosVersion=$(dmidecode -t0 | grep "Version\|Release" | sort -ru | awk '{print $NF}' | tr '\n' ' ')
declare MTConfigFile=$(xmlstarlet sel -t -v "//MainProg/Multithreading/TestCase[ProgramName=\"Multithreading\"]/ConfigFile" -n ${XmlConfigFile} )
declare PTEName PEName ReleaseDate Update BootSN ErrorsOccurredChk
export MainLog ModelName BiosFile BmcFile EepromFile MpsFW APVersion PathAndShellName
export ProcLog ProcID Path pcb TestStation
export FailLocking FailUpload IndexInUse NgLockWebSite MesWebSite FailCntLimit
declare PortIndex NetcardName MacAddr LinkStatus
declare ErrorCodeFile="${MainDir}/PPID/ErrorCode.TXT"
declare Md5Path="${MainDir}/PPID/ChkMD5"
declare StdMD5="${Md5Path}/StdMD5"
declare Encrypt EncryptPassword
declare StartIndex EndIndex StartParalle
GetParametersFrXML

# if=0(APVersion include letter "L"),check the status,if=other,skip it
echo "${FailLocking}" | grep -iq "enable" && APVersion=$(echo "${APVersion}L")
echo "${FailUpload}" | grep -iq "enable" && APVersion=$(echo "${APVersion}U")
echo "${Encrypt}" | grep -iq "enable" && APVersion=$(echo "${APVersion}S")
export LockFlag=$(echo ${APVersion} | grep -ivc "l") 

#測試項目索引數組，多線程算1項
declare TotalItemIndex=($(xmlstarlet sel -t -v "//Programs/Item/@index" -n ${XmlConfigFile} | sort -nu ))
if [ $(echo "${TotalItemIndex[@]}" | grep -iEc "[A-Z]") -ge 1 ] ; then
	Process 1 "Invalid index: `echo "${TotalItemIndex[@]}" | tr ' ' '\n' | grep -iE '[A-Z]' | tr '\n' ' ' | sed 's/ /,/g'`"
	exit 3
fi 

declare CurPPID=$(cat ${MainDir}/PPID/PPID.TXT 2>/dev/null)

# Ignoring  OP hit on Ctrl+C(2), Ctrl+/(3),Ctrl+Z(24), e.g.
echo ${APVersion} | grep -iq "l\|s" && trap '' INT QUIT TSTP HUP 

# Check the associated files and folders
CheckAssociatedFiles

# Check the test program is not modify yet
EncryptTestProgram

# Check the logic of TestAP
echo "${CheckLogic}" | grep -iwq "enable" && { sh ${MainDir}/ChkLogic/ChkLogic.sh -x ${XmlConfigFile} 2>/dev/null || exit 1;}

#CheckParameter
#Begin to record time
exec ${MainDir}/time_stamp.sh &

# Input PCB Serial Number
clear
ShowHeader 
#sh ${MainDir}/Scan/ScanPPID.sh -x ${XmlConfigFile}
# for batch function test
for((C=0;C<3;C++))
do
	sh ${MainDir}/Scan/ScanSNs.sh -x ${XmlConfigFile} 
	ScanResult=${?}
	case ${ScanResult} in
		0)break;;
		9)exit 1;;
		*)continue;;
		esac
done
# if fail more than 3time ,test logs will be deleted
if [ $C == 3 ] ; then
	sh ${MainDir}/DelLog/DelLog.sh -x ${XmlConfigFile} 2> /dev/null
	exit 1
fi
	
	
# declare the MainLog
pcb=$(cat ${MainDir}/PPID/PPID.TXT 2>/dev/null)
MainLog="${MainDir}/PPID/${pcb}.log"

# Initializing the current process ID
if [ "${#pcb}" -gt "0" ] && [ -f "${MainDir}/PPID/${pcb}.proc" ] ; then 
	ProcLog=$(cat ${MainDir}/PPID/${pcb}.proc 2>/dev/null)
else
	ProcLog=0
fi
ProcID=1

# Begin to test
if [ -e "${MainLog}" ] && [ ${#pcb} != 0 ] ; then
	echo -e "\e[1;36m ${pcb}, ${ModelName}, test continue ...  \e[0m" | tee -a "${MainLog}"
else
	clear
	rm -rf "${MainLog}" 2>/dev/null
	
	# Show the main log again
	ShowHeader | tee -a "${MainLog}"
	cat ${MainDir}/Scan/ScanSNs.log >>  ${MainLog} 2>&1
	echo "Program running start in: `date "+%Y-%m-%d %H:%M:%S %A %Z"`"  | tee -a "${MainLog}"
	echo "The serial number of ${ModelName} is: ${pcb}"  | tee -a "${MainLog}"
	echo "${APVersion},${Update},`md5sum ${MainDir}/${BaseName}.sh ${MainDir}/PPID/ChkMD5/StdMD5 2>/dev/null | awk '{print $1}' |cut -c 29-32 | tr -d '\n'`" >${MainDir}/PPID/TPVER.TXT
	echo "${ModelName}" > ${MainDir}/PPID/MODEL.TXT
	echo "OSVer: `uname -r`" > ${MainDir}/PPID/OS.TXT
	sync;sync;sync
fi

# if the M/B can connect the server
if [ $(echo ${APVersion} | grep -ic "l") -ge 1 ] ; then
	ConfirmStationStatus
	if [ $? != 0 ] ; then
		exit 1
	else
		LockFlag=1
	fi
fi
# 检查并行运行的设定，如果不使用自动测试，则按正常顺序执行，如果执行并行测试，则检查对应3个参数StartParalle<StartIndex<=EndIndex,如果不符合设定，则直接Fail，PASS则开始转换index

# 设定的config 时，只需要输入对应开始的项目前的index 即可，如下脚本会将其转换为对应的执行顺序index
if [ ${EndIndex} == 0 ];then
	echo "Paralle Test is disabled"
	StartParalle=${StartParalle:-7}
	StartIndex=${StartIndex:-19}
else
	if [ ${EndIndex} -ge ${StartIndex} ] && [ ${StartIndex} -gt ${StartParalle} ];then
		for ((z=0;z<${#TotalItemIndex[@]};z++))
		do
			if [ ${TotalItemIndex[$z]} -eq ${StartParalle} ];then
				StartParalle=$z
				continue
			elif  [ ${TotalItemIndex[$z]} -eq ${StartIndex} ];then
				StartIndex=$z
				continue
			else
				if [ ${TotalItemIndex[$z]} -eq ${EndIndex} ];then
					EndIndex=$z
				fi
			fi
		done
	else
		Process 1 "并行测试参数 StartParalle, StartIndex, EndIndex 设定错误，请确认！！"
		exit 3
	fi
fi



#================================Run the test programs==========================================
# Only for Shell program. The Shell must return Pass (0) or Fail (!=0).
#------------------------------------------------------------------------------------------
#update: 更新后item的index號可以不是連續的自然數

for ((z=0;z<${#TotalItemIndex[@]};z++))
do
	rm -rf ${BaseName}.ini 2>/dev/null
	xmlstarlet sel -t -v  //Programs/Item[@index=${TotalItemIndex[z]}] ${XmlConfigFile} 2>/dev/null | grep -iE '[0-9A-Z]' | grep -v "^$" >${BaseName}.ini
	sync;sync;sync
	
	if [ ! -s "${BaseName}.ini" ] ; then
		Process 1 "No such file or 0 KB size of file: ${BaseName}.ini"
		exit 2	
	fi
	
	ProgramFileSet=($(cat ${BaseName}.ini 2>/dev/null | grep -v "#" | grep -v "^$" ))
	ProgramNameSet=($(cat ${BaseName}.ini 2>/dev/null | grep -v "#" | grep -v "^$" | awk -F'|' '{print $1}' | awk -F'/' '{print $NF}' ))
	case ${#ProgramNameSet[@]} in
		0)	
			Process 1 "${BaseName}.ini is NULL" 
			exit 2
			;;
		*)	
			
			if [ $ProcID -gt ${StartIndex} ] && [ $ProcID -le ${EndIndex} ];then
				while :
				do					
					ps -aux | grep -i "Paralle.sh" |grep -iv "grep" |grep -iv "gedit" >/dev/null 2>&1
					if [ $? == 0 ];then
						echo "The background process is still running,please waiting" | tee -a ${MainLog}
						sleep 2
					else
						break
					fi
				done
			fi
			# run some item in another terminal window
			
			# Get a unique name
			ProgramNameSet=($(echo ${ProgramNameSet[@]} | tr ' ' '\n' | sort -u ))
			ProgramNameSet=$(echo ${ProgramNameSet[@]} | sed 's/ /\\|/g')
			TestPassCnt=$(cat -v ${MainLog} 2>/dev/null | grep -w ${ProgramNameSet} | tr -d ' ' | grep -ic "TestPass")
			echo $ProcID $ProcLog |tee -a ${MainLog}
			#if [ ${TestPassCnt} -ge ${#ProgramNameSet[@]} ] && [ ${ProcID} -le ${ProcLog} ] ; then
			if [ ${TestPassCnt} -ge ${#ProgramNameSet[@]} ] && [ $ProcID  -gt ${StartIndex} ] && [ $ProcID -le ${EndIndex} ]; then
				# Current item(s) have been test pass
				ProcID=$((${ProcID}+1))
				continue
			elif
				[ ${TestPassCnt} -ge ${#ProgramNameSet[@]} ] && [ ${ProcID} -le ${ProcLog} ];then
				# Current item(s) have been test pass
				ProcID=$((${ProcID}+1))
				continue
			else
				if [ $ProcID -gt ${StartParalle} ] && [ $ProcID -lt ${EndIndex} ]; then
				ps -aux |grep -i "Paralle.sh" |grep -iv "grep" |grep -iv "gedit" >/dev/null 2>&1
					if [ $? != 0 ];then
					gnome-terminal --window -- bash -c "/TestAP/Test/Paralle.sh -x ${XmlConfigFile};exec bash"
					fi
				fi
				clear
				if [ ${#ProgramNameSet[@]} -gt 1 ] ; then
					rm -rf .${BaseName}.TXT >/dev/null 2>&1
					for((T=0;T<${#ProgramFileSet[@]};T++))
					do	
						PathAndShellName=$(echo "${ProgramFileSet[$T]}" | awk -F'|' '{print $1}')
						# Save the log in MainLog
						IgnoreSpecTestItem ${PathAndShellName} ${TotalItemIndex[z]} >/dev/null 2>&1
						if [ $? == 0 ] ; then
							echo "${PathAndShellName}" >> .${BaseName}.TXT
						else
							echo "Create the config file for multithreading program ..." | tee -a "${MainLog}"
							IgnoreSpecTestItem ${PathAndShellName} ${TotalItemIndex[z]} 2>&1 | tee -a "${MainLog}"
							echo "${ProgramFileSet[$T]}" | sed 's/|/ test pass, because no found any model name of /g'  >> "${MainLog}"
							echo "Auto to check next item ..." | tee -a "${MainLog}"
							sync;sync;sync
						fi
					done
				
					if [ -s ".${BaseName}.TXT" ] ; then
						mv -f .${BaseName}.TXT ${BaseName}.ini  >/dev/null 2>&1
					else
						ProcID=$((${ProcID}+1))
						echo "${ProcID}" > ${MainDir}/PPID/${pcb}.proc
						md5sum ${MainDir}/PPID/${pcb}.proc > ${MainDir}/PPID/.procMD5
						sync;sync;sync
						continue
					fi
					
					cp ${BaseName}.ini ${MTConfigFile} >/dev/null 2>&1 || exit 255
					sync;sync;sync
				fi
				
				Run ${BaseName}.ini
			fi		
			;;
	esac	
done

# -----------------------Finish all test programs and upload test result to MES------------------------------------
for((w=5;w>0;w--))
do
	rm -rf ${MainDir}/PPID/.BreakOut.txt 2>/dev/null
	{ 
		rm -rf ${MainDir}/PPID/PCBAProductInfo.TXT 2>/dev/null
		sh ${MainDir}/GetPrdctInfo/GetMDL.sh -x ${XmlConfigFile} 2>/dev/null
		if [ $? != 0 ] ; then
			Wait4nSeconds 20 || echo "1" > ${MainDir}/PPID/.BreakOut.txt
			continue
		fi
		sync;sync;sync;
	} 2>&1 | tee -a "${MainLog}"
	
	grep -wq "1" "${MainDir}/PPID/.BreakOut.txt" 2>/dev/null && exit 1
	
	{ 
		# Upload test log file and upload test result to the MES
		sh ${MainDir}/PPID/Pass.sh -x ${XmlConfigFile} 
		if [ $? == 0 ] ; then
			echo "0" > ${MainDir}/PPID/.BreakOut.txt
		else
			Wait4nSeconds 3599 || echo "1" > ${MainDir}/PPID/.BreakOut.txt
			continue
		fi
		sync;sync;sync;
	} 2>&1 | tee -a "${MainLog}"
	
	grep -wq "1" "${MainDir}/PPID/.BreakOut.txt" 2>/dev/null && exit 1	
	grep -wq "0" "${MainDir}/PPID/.BreakOut.txt" 2>/dev/null && break	
	
done

# TestAP load default,Before delete logs,OPs have n sec to confirm
sh ${MainDir}/DelLog/DelLog.sh -x ${XmlConfigFile}

# Test finished and shutdown
sh ${MainDir}/Shutdown/Finish.sh
