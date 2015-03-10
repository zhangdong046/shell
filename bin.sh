#!/bin/sh

## 如果启动服务名为空则输出错误
if [ "$1" == "" ]; then
	echo "no start process"
	exit 1
fi

## 启动服务名称
CURDIR=`cd $(dirname $0);pwd`
BIN_NAME="$CURDIR/bin/$1"

cd $CURDIR >/dev/null

mkdir -p $CURDIR/{shelllog,log}

## 获取当前进程
SERVER_STR=`ps -ef | grep $BIN_NAME | grep -v grep | awk -F' ' '{print $1":"$8":"$2}'`

## 遍历所有服务
for k in $SERVER_STR
do
   ID=`awk -v var=$k 'BEGIN{print var}' | awk -F: '{print $3}'`
   NAME=`awk -v var=$k 'BEGIN{print var}' | awk -F: '{print $2}'`
   LOGIN_NAME=`awk -v var=$k 'BEGIN{print var}' | awk -F: '{print $1}'`
#   if [[ $NAME =~ "/$BIN_NAME$" ]]; then 
   		kill -9 $ID >/dev/null
   		echo "Login_Name:"$LOGIN_NAME" Process:"$NAME" PID:"$ID" Status:" "KILL !!!"
   	 	usleep 10
#   fi
done

## 判断是否停止服务，则不再启动
if [ -z "$2" ]; then 
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CURDIR/so:$CURDIR/so/rules >/dev/null
	TEMP="$BIN_NAME $CURDIR"
	echo $TEMP
	$TEMP& >/dev/null
fi

exit 0