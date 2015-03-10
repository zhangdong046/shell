#!/bin/bash

#参数检查
if [ $# != 1 ]; then
    echo "Parameter: $0 Sw_file_path" 
    exit 1
fi

#文件预查
DIR=$1
`cd $DIR/Addition >/dev/null 2>&1` && `cd $DIR/level2 >/dev/null 2>&1`
if [ $? != 0 ]; then
    echo "File path error!"
    exit 1
fi

#辅助目录创建
DIR=$1
`cd ./result >/dev/null 2>&1`
if [ $? != 0 ]; then
    mkdir result
fi

#判空和编码检查
Check(){
for file in $1/*
    do
        if [ -d $file ]; then
            Check $file
        elif [ -s $file ]&&[ `echo $file | grep -e  '.mid' -e '.mif'` ]; then
            file $file | awk '{print  $1"\t" $2"\t"}'>>./result/file_code.log
        elif [[ ! -s $file ]]&&[ `echo $file | grep -e  '.mid' -e '.mif'` ]; then
            echo ${file##*/}>>./result/file_null.log
        fi
    done
}

#判断存在
Judge(){
find $DIR/level2 $DIR/Addition -name "$1" -type f| xargs wc -cl | awk '{print $2}'>./result/file_tmp.log
while read line
    do
        if [ "$line"x = "0"x ]; then
            echo $1>>./result/file_miss.log
            echo "Some data is missing!"
        fi                
    done<./result/file_tmp.log
}

#主函数
Process(){

#获取城市名称
cityname=()
declare -i flag=0
for file in $1/*
    do
        if [ -d $file ]; then
            ctnm=${file##*/}
            cityname[$flag]=$ctnm
            flag=flag+1
        fi
    done
echo ${cityname[*]} 

#预处理
files="A Ac Admin BL BN BP BPL BUP C CNL Cond CR D Dr FName IC N PName POI POI_Relation R R_LName R_LZone R_Name T TrfcSign Z Z_Level Signboard CrossNode VirtualConn CrossWalk DC_R SpeedCamera Br Ln Dm"
find ./result -name "file_*.log"  -exec rm -rf {} \;
Check $DIR
if [ -a ./result/file_null.log ]; then
    echo "Some file's size is 0!"
fi

#核对文件缺失情况
for city in ${cityname[@]}
    do
        for name2 in $files
            do
                tmp1=$name2${city}.mid
                tmp2=$name2${city}.mif
                #echo $tmp1>>./a.txt
                Judge $tmp1
                Judge $tmp2
            done
    done
}

#配置含城市名称的目录
temps=${DIR%/*}
city_dir=$temps/level2
Process $city_dir
find ./result -name "file_tmp.log"  -exec rm -rf {} \;
