#!/bin/bash
curdir=`cd $(dirname $0);pwd`
cd $curdir

source /etc/profile
source ~/.bash_profile
source conf/db_conf
source conf/web.conf
source function



function usage()
{
    cat <<"EOT";
Usage: export_gaode&siwei.sh -d source -f type -a [-p prefix]
    -d      Choose data source  
            1 siwei
            2 gaode
    -f      The data type
            0 road_all(siwei)
            1 road(siwei&gaode)
            2 backgound(siwei)
            3 building(siwei&gaode)
            4 POI(gaode)
    -a      area code 110000  420100 430100 430600
    -i      task id
EOT
}

function exec_stacheck(){
    echo 'start sta or check...'
	if [[ $sourcename = "1" ]]; then
        `cd ${python_cmd_path};python statisSWOrigMifMain.py ${filepath} ${taskid} ${admpy}`
		check_result=`cd ${python_cmd_path};python sw_export_check.py ${filepath} ${taskid} ${admpy} ${typename}`
        [[ "${check_result/'check_status_fail'/}" != $check_result  ]] && update_taskinfo "check_status" 1 || update_taskinfo "check_status" 0
    else
        `cd ${python_cmd_path};python statGdMifMain.py ${filepath} ${taskid} ${admpy}`
        check_result=`cd ${python_cmd_path};python gd_export_check.py ${filepath} ${taskid} ${admpy} ${typename}`
      [[ "${check_result/'check_status_fail'/}" != $check_result  ]] && update_taskinfo "check_status" 1 || update_taskinfo "check_status" 0
	fi
}

function exec_url(){
	exec_stacheck
    
    `cd ${filepath};zip -q "${admpy}.zip" *`
    `cd ${filepath};rm -f *.mif *.mid`

	## if need net copy file 
    if  [ ! -z "$net_storage_root" ]
    then
	local filename=${admpy}.zip
        local net_dir=$net_storage_root/${replace_path}
        create_dir $net_dir
        cp -rf $filepath/$filename $net_dir
        chmod 777 $net_dir/$filename
    fi

    zippath=$filepath/${admpy}.zip
    curl $web_local_url'/dataservice/api/fileinfoapi?filepath='$zippath'&uuid='$uuid
    url=$web_wide_url'/dataservice/fileinfo?uuid='$uuid

	update_taskinfo "url" "'$url'"
	update_taskinfo "progress" 100
	update_taskinfo "status" 1
    suc "${url}"
}

function exec_export(){
    sql=$1
    tname=$2
	progress=$3
    admincode=`tr -d "\'" <<< $admincode`
    create_dir  $filepath
    if [[ $sourcename = "1" ]]; then
        dbname="${siwei_db}"
    else
        dbname="${gaode_db}"
        if [[ $typename = "1" ]]; then
            if [ -s "${filepath}/${tname}${admpy}.mif"  -a  -s "${filepath}/${tname}${admpy}.mid" ]; then
                update_taskinfo "progress" $progress
                return 0
            else
                update_taskinfo "status" -1
                return 1
            fi
        fi
    fi
    cmd="ogr2ogr -f \"MapInfo File\" ${filepath}/${admincode}_${tname}.mif MySQL:${dbname},user=${mysql_user},password=${mysql_password},host=${mysql_host},port=${mysql_port} -dsco FORMAT=MIF -sql $sql"
    #echo $cmd
    bash -c "$cmd" ||  fail "org2org fail"
    if [[ ${tname:0:6} = 'gd_poi' ]]; then
        tail +34 ${filepath}/${admincode}_${tname}.mif > ${filepath}/${admincode}_${tname}.mift
        cat $curdir/conf/gd_poi_head.mif ${filepath}/${admincode}_${tname}.mift > ${filepath}/${admincode}_${tname}.mif      
    fi
    # line_num=$(cat $file | wc -l)
    # if [ $line_num = 0 ]
    # then
    #     fail "no road data, may be polygon is invalid or choose another polygon"
    # fi
	update_taskinfo "progress" $progress
    iconv -f UTF-8 -t GB18030 ${filepath}/${admincode}_${tname}.mif > ${filepath}/${admincode}_${tname}_utf8.mif  || fail "iconv error"
    iconv -f UTF-8 -t GB18030 ${filepath}/${admincode}_${tname}.mid  > ${filepath}/${admincode}_${tname}_utf8.mid || fail "iconv error"
    rm  -rf  ${filepath}/${admincode}_${tname}.mi*
    mv -f ${filepath}/${admincode}_${tname}_utf8.mif  ${filepath}/${tname}${admpy}.mif
    mv -f ${filepath}/${admincode}_${tname}_utf8.mid  ${filepath}/${tname}${admpy}.mid
}   

function export_road(){
    admincode="'$admincode'"
    if [[ "$sourcename" = "2" ]]; then
        #sql_r="\"SELECT r.* FROM road r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode\""
        exec_export "" "gd_road"  50
        if [[ $? -eq 1 ]]; then
            return 1
        fi
        exec_url  "gd_road"
        return 0
    else
		sql_r="\"SELECT r.shape, r.MapID, r.id, r.Kind_num, r.Kind, r.width, r.Direction, r.Toll, r.Const_St, r.UndConCRID, r.SnodeID, r.EnodeID, 
				r.FuncClass, r.Length, r.DetailCity, r.Through, r.UnThruCRID, r.Ownership, r.Road_Cond, r.Special, r.AdminCodeL, r.AdminCodeR, 
				r.Uflag, r.OnewayCRID, r.AccessCRID, r.SpeedClass, r.LaneNumS2E, r.LaneNumE2S, r.LaneNum, r.Vehcl_Type, r.Elevated, r.Structure, 
				r.UseFeeCRID, r.UseFeeType, r.SpdLmtS2E, r.SpdLmtE2S, r.SpdSrcS2E, r.SpdSrcE2S, r.DC_Type, r.NoPassCRID FROM r r, admarea_city c 
				WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode\""
		sql_rlname="\"SELECT n.MapID, n.id, n.Route_ID, n.Name_Kind, n.Name_Type, n.Seq_Nm FROM r_lname n join r r on r.id=n.id join admarea_city c on ST_Intersects(c.SHAPE, r.SHAPE) where c.admincode =$admincode\""
		sql_rname="\"Select n.Route_ID, n.Route_Kind, n.PathName, n.PathPY, n.PreName, n.PrePY, n.BaseName, n.BasePY, n.StTpName, n.StTpPY, n.SurName, 
				n.SurPY, n.WavName, n.Language, n.StTpLoc FROM r_name n join r_lname lname on n.route_id=lname.route_id join r r on lname.id=r.id join admarea_city c on ST_Intersects(c.SHAPE, r.SHAPE) where c.admincode =$admincode\""
		sql_rlzone="\"Select l.MapID, l.id, l.ZoneID, l.Side, l.ZType from r_lzone l join r r on l.id=r.id join admarea_city c on ST_Intersects( c.SHAPE, r.SHAPE ) where c.admincode =$admincode\""
		sql_n="\"Select n.shape, n.MapID, n.id, n.Kind_num, n.Kind, n.Cross_flag, n.Light_flag, n.Cross_LID, n.mainNodeID, n.subNodeID, n.subNodeID2,
				n.Adjoin_MID, n.Adjoin_NID, n.Node_LID FROM n n, admarea_city c WHERE ST_Intersects(c.SHAPE, n.SHAPE) AND c.admincode =$admincode\""
		sql_c="\"Select c.shape, c.MapID, c.CondID, c.id, c.inLinkID, c.outLinkID, c.CondType, c.CRID, c.Passage, c.Slope, c.SGNL_LOCTION FROM c c, admarea_city adm WHERE ST_Intersects(adm.SHAPE, c.SHAPE) AND adm.admincode =$admincode\""
		sql_cond="\"Select cond.MapID, cond.CondID, cond.CondType, cond.CRID, cond.Passage, cond.Slope, cond.SGNL_LOCTION 
				FROM cond cond,(SELECT distinct r.mapid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode=$admincode) a
				where cond.mapid=a.mapid\""
		sql_cnl="\"Select cnl.MapID, cnl.CondID, cnl.LinkID, cnl.NodeID, cnl.Seq_Nm, cnl.Angle
				FROM cnl cnl,(SELECT distinct r.mapid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode=$admincode) a
				where cnl.mapid=a.mapid\""
		sql_cr="\"Select cr.CRID, cr.VPeriod, cr.VPDir, cr.Vehcl_Type, cr.VP_Approx FROM cr cr join c c on cr.crid=c.crid join admarea_city adm on ST_Intersects(adm.SHAPE, c.SHAPE) 
				where adm.admincode=$admincode
				union
				Select cr.CRID, cr.VPeriod, cr.VPDir, cr.Vehcl_Type, cr.VP_Approx FROM cr cr ,(
				SELECT r.NoPassCRID FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode) a 
				where a.NoPassCRID=cr.crid\""
		sql_ss="\"Select s.MapID, s.ID, s.Type, s.SpeedLimit, s.Dependent, s.CRID FROM special_speed s join r r on r.id=s.id join admarea_city adm on ST_Intersects(adm.SHAPE, r.SHAPE) where adm.admincode =$admincode\""
		sql_ic="\"Select i.shape, i.MapID, i.id, i.NodeID, i.inLinkID, i.outLinkID, i.WavName, i.PassLid FROM ic i, admarea_city c WHERE ST_Intersects(c.SHAPE, i.SHAPE) AND c.admincode =$admincode\""
		sql_dr="\"Select d.shape, d.MapID, d.id, d.NodeID, d.inLinkID, d.outLinkID, d.WavName, d.PassLid, d.PassLid2, d.type FROM dr d, admarea_city c WHERE ST_Intersects(c.SHAPE, d.SHAPE) AND c.admincode =$admincode\""
		sql_zl="\"Select z.shape, z.MapID, z.id, z.Seq_Nm, z.Z, z.LinkType, z.Level_ID FROM z_level z, admarea_city c WHERE ST_Intersects(c.SHAPE, z.SHAPE) AND c.admincode =$admincode\""
		sql_trfc="\"Select t.MapID, t.inLinkID, t.NodeID, t.type, t.ValidDist, t.PreDist, t.CRID FROM trfcsign t join r r on t.inlinkid=r.id join admarea_city c on ST_Intersects( c.SHAPE, r.SHAPE ) where c.admincode =$admincode\""
		sql_ln="\"Select l.shape, l.MapID, l.NodeID, l.inLinkID, l.outLinkID, l.LaneNum, l.LaneInfo, l.ArrowInfo, l.LaneNumL, l.LaneNumR, l.PassLid, 
				l.PassLid2, l.BusLane FROM ln l, admarea_city c WHERE ST_Intersects(c.SHAPE, l.SHAPE) AND c.admincode=$admincode\""
        
        exec_export "$sql_r"  "R" 10
        exec_export "$sql_rlname"  R_Lname 15
        exec_export "$sql_rname"  R_Name  20
        exec_export "$sql_rlzone"  R_Lzone 25
        exec_export "$sql_n" N 30
        exec_export "$sql_c"  C 35
        exec_export "$sql_cond"  Cond 40
        exec_export "$sql_cnl"  CNL 45
        exec_export "$sql_cr" CR 50
        exec_export "$sql_ss" Special_Speed 55
        exec_export "$sql_ic"  IC 60
        exec_export "$sql_dr"  Dr 65
        exec_export "$sql_zl" Z_Level 70
        exec_export "$sql_trfc" TrfcSign 75
        exec_export "$sql_ln"  Ln 90
        exec_url "road"
    fi

}

function export_building(){
    admincode="'$admincode'"
    if [[ $sourcename = "2" ]]; then
        sql_building="\"SELECT b.* FROM building b, admarea_city c WHERE ST_Intersects(c.SHAPE, b.SHAPE) AND c.admincode =$admincode\""
        exec_export "$sql_building" "gd_building" 60
        exec_url "gd_building"
    else
        provcode=$(expr substr "$admincode" 2 2)
        sql_building="\"SELECT b.* FROM building b WHERE b.admincode = '${provcode}0000'\""
        exec_export "$sql_building" "Building" 60
        exec_url "building"
    fi
    

}

function export_bg(){
	cityadcode=${admincode:0:4}
    admincode="'$admincode'"
    sql_bn="\"Select bn.shape, bn.MapID, bn.ID, bn.Kind_num, bn.Kind, bn.Adjoin_MID, bn.Adjoin_NID, bn.Node_LID FROM bn bn join admarea_city c on ST_Intersects(c.SHAPE, bn.SHAPE) AND c.admincode =$admincode\""
    sql_bl="\"Select bl.shape, bl.MapID, bl.ID, bl.Kind, bl.Snode_ID, bl.Enode_ID FROM bl bl join admarea_city c on ST_Intersects(c.SHAPE, bl.SHAPE) AND c.admincode =$admincode\""
    sql_bp="\"Select bp.shape, bp.MapID, bp.ID, bp.Kind, bp.AdminCode, bp.AOICode, bp.DispClass FROM bp where kind='0137' and admincode like '$cityadcode%'
			union
			Select bp.shape, bp.MapID, bp.ID, bp.Kind, bp.AdminCode, bp.AOICode, bp.DispClass FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) and bp.admincode='' AND c.admincode =$admincode\""
    sql_bpl="\"Select bpl.MapID, bpl.Polygon_ID, bpl.Link_ID, bpl.Seq_Num, bpl.Orient FROM bpl bpl,(
			Select bp.id FROM bp where kind='0137' and admincode like '$cityadcode%'
			union
			Select bp.id FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) and bp.admincode='' AND c.admincode=$admincode) a 
			where bpl.polygon_id=a.id\""
    sql_bup="\"Select bup.UnionP_ID, bup.MapID, bup.Polygon_ID, bup.Kind, bup.AdminCode, bup.AOICode, bup.DispClass FROM bup bup,(
			Select bp.id FROM bp where kind='0137' and admincode like '$cityadcode%'
			union
			Select bp.id FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) and bp.admincode='' AND c.admincode =$admincode) a
			where bup.polygon_id=a.id\""
    sql_d="\"Select d.shape, d.AdminCode, d.Kind FROM d d where d.admincode like '$cityadcode%'\""
	sql_fname="\"select fn.FeatID, fn.NameType, fn.Name, fn.PY, fn.KeyWord, fn.Seq_Nm, fn.SignNumFlg, fn.SignNameTp, fn.Language, fn.NameFlag from fname fn,(
		SELECT bl.id FROM bl bl join admarea_city c on ST_Intersects(c.SHAPE, bl.SHAPE) AND c.admincode=$admincode
		union all
		SELECT bp.id FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) AND c.admincode=$admincode
		union all
		SELECT bup.unionp_id id FROM bup bup join bp bp on bup.polygon_id=bp.id join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) AND c.admincode=$admincode
		) a where fn.featid = a.id\""

    exec_export "$sql_bn"  "BN" 20
    exec_export "$sql_bl"  "BL" 40
    exec_export "$sql_bp"  "BP" 50
    exec_export "$sql_bpl"  "BPL" 70
    exec_export "$sql_bup"  "BUP" 85
    exec_export "$sql_d"  "D" 90
	exec_export "$sql_fname"  "FName" 95

    exec_url "bg"
}

function export_all(){
	cityadcode=${admincode:0:4}
    provadcode=${admincode:0:2}
    admincode="'$admincode'"
    #文本数据
    sql_t="\"Select t.shape, t.MapID, t.ID, t.Kind, t.Class FROM t t join admarea_city c on ST_Intersects(c.SHAPE, t.SHAPE) AND c.admincode =$admincode\""
    #索引数据
    sql_poi="\"Select p.shape, p.MapID, p.Kind, p.ZipCode, p.Telephone, p.AdminCode, p.Display_X, p.Display_Y, p.POI_ID, p.Importance, p.VAdmincode, 
			p.ChainCode, p.Prior_Auth, p.LinkID, p.Side, p.PID, p.Tel_Type, p.Food_Type, p.Airpt_Code, p.Open_24H, p.Data_Src, p.Mesh_ID 
			FROM poi p join admarea_city c on ST_Intersects(c.SHAPE, p.SHAPE) AND c.admincode =$admincode\""
    sql_pr="\"Select DISTINCT pr.POI_ID1, pr.POI_ID2, pr.Rel_Type FROM poi_relation pr,(select p.poi_id FROM poi p join admarea_city c on ST_Intersects(c.SHAPE, p.SHAPE) AND c.admincode=$admincode) a
			where pr.poi_id1=a.poi_id or pr.poi_id2=a.poi_id\""
    sql_hamlet="\"Select h.shape, h.MapID, h.Kind, h.ZipCode, h.Telephone, h.AdminCode, h.Display_X, h.Display_Y, h.POI_ID, h.Importance, h.VAdmincode, 
			h.ChainCode, h.Prior_Auth, h.LinkID, h.Side, h.PID, h.Tel_Type, h.Food_Type, h.Airpt_Code, h.Open_24H, h.Data_Src, h.Mesh_ID 
			FROM hamlet h join admarea_city c on ST_Intersects(c.SHAPE, h.SHAPE) AND c.admincode =$admincode\""
    sql_z="\"Select z.shape, z.ZipCode, z.AdminCode FROM z z join admarea_city c on ST_Intersects(c.SHAPE, z.SHAPE) AND c.admincode =$admincode\""
    sql_a="\"Select a.shape, a.Class, a.AdminCode, a.Center, a.Population, a.LinkID, a.Side, a.Dummy FROM a a join admarea_city c on ST_Intersects(c.SHAPE, a.SHAPE) AND c.admincode =$admincode\""
    sql_ac="\"Select ac.shape, ac.MapID, ac.ID, ac.AdminCode FROM ac ac join admarea_city c on ST_Intersects(c.SHAPE, ac.SHAPE) AND c.admincode =$admincode\""
    #other数据
    sql_admin="\"Select AdminCode, CityAdCode, ProAdCode from admin where cityadcode like '$cityadcode%'\""
    sql_pname="\"Select pn.FeatID, pn.NameType, pn.name, pn.PY, pn.KeyWord, pn.Seq_Nm, pn.SignNumFlg, pn.SignNameTp, pn.Language, pn.NameFlag 
			from pname pn join poi p on pn.featid=p.poi_id join admarea_city c on ST_CONTAINS(c.SHAPE, p.SHAPE) AND c.admincode=$admincode;\""
    sql_hmname="\"Select hn.FeatID, hn.NameType, hn.Name, hn.PY, hn.KeyWord, hn.Seq_Nm, hn.SignNumFlg, hn.SignNameTp, hn.Language, hn.NameFlag 
			from hmname hn join hamlet h on hn.featid=h.poi_id join admarea_city c on ST_CONTAINS(c.SHAPE, h.SHAPE) AND c.admincode=$admincode\""
    sql_fname="\"Select fn.FeatID, fn.NameType, fn.Name, fn.PY, fn.KeyWord, fn.Seq_Nm, fn.SignNumFlg, fn.SignNameTp, fn.Language, fn.NameFlag from fname fn,(
			select l.zoneid id from r_lzone l join r r on l.id=r.id join admarea_city c on ST_Intersects( c.SHAPE, r.SHAPE ) where c.admincode=$admincode
			union
			SELECT i.id id FROM ic i, admarea_city c WHERE ST_Intersects(c.SHAPE, i.SHAPE) AND c.admincode=$admincode
			union
			SELECT d.id id FROM dr d, admarea_city c WHERE ST_Intersects(c.SHAPE, d.SHAPE) AND c.admincode=$admincode
			union
			SELECT bl.id id FROM bl bl join admarea_city c on ST_Intersects(c.SHAPE, bl.SHAPE) AND c.admincode=$admincode
			union
			SELECT bp.id id FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) AND c.admincode=$admincode
			union
			SELECT bp.id id FROM bp where kind='0137' and admincode like '$cityadcode%'
			union
			SELECT bp.id id FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) and bp.admincode='' AND c.admincode=$admincode
			union
			SELECT bup.unionp_id id FROM bup bup join bp bp on bup.polygon_id=bp.id join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) AND c.admincode=$admincode
			union
			SELECT t.id id FROM t t join admarea_city c on ST_Intersects(c.SHAPE, t.SHAPE) AND c.admincode=$admincode
			union
			SELECT ac.id id FROM ac ac join admarea_city c on ST_Intersects(c.SHAPE, ac.SHAPE) AND c.admincode=$admincode
			union
			select cityadcode id FROM admin where cityadcode=$admincode
			union
			SELECT n.id id FROM n n, admarea_city adm WHERE ST_Intersects(adm.SHAPE, n.SHAPE) AND adm.admincode=$admincode
			union
			SELECT c.condid id FROM c c, admarea_city adm WHERE ST_Intersects(adm.SHAPE, c.SHAPE) AND adm.admincode=$admincode
			) a where fn.featid = a.id\""
	#背景数据
    sql_bn="\"Select bn.shape, bn.MapID, bn.ID, bn.Kind_num, bn.Kind, bn.Adjoin_MID, bn.Adjoin_NID, bn.Node_LID FROM bn bn join admarea_city c on ST_Intersects(c.SHAPE, bn.SHAPE) AND c.admincode =$admincode\""
    sql_bl="\"Select bl.shape, bl.MapID, bl.ID, bl.Kind, bl.Snode_ID, bl.Enode_ID FROM bl bl join admarea_city c on ST_Intersects(c.SHAPE, bl.SHAPE) AND c.admincode =$admincode\""
    sql_bp="\"Select bp.shape, bp.MapID, bp.ID, bp.Kind, bp.AdminCode, bp.AOICode, bp.DispClass FROM bp where kind='0137' and admincode like '$cityadcode%'
			union
			Select bp.shape, bp.MapID, bp.ID, bp.Kind, bp.AdminCode, bp.AOICode, bp.DispClass FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) and bp.admincode='' AND c.admincode =$admincode\""
    sql_bpl="\"Select bpl.MapID, bpl.Polygon_ID, bpl.Link_ID, bpl.Seq_Num, bpl.Orient FROM bpl bpl,(
			Select bp.id FROM bp where kind='0137' and admincode like '$cityadcode%'
			union
			Select bp.id FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) and bp.admincode='' AND c.admincode=$admincode) a 
			where bpl.polygon_id=a.id\""
    sql_bup="\"Select bup.UnionP_ID, bup.MapID, bup.Polygon_ID, bup.Kind, bup.AdminCode, bup.AOICode, bup.DispClass FROM bup bup,(
			Select bp.id FROM bp where kind='0137' and admincode like '$cityadcode%'
			union
			Select bp.id FROM bp bp join admarea_city c on ST_Intersects(c.SHAPE, bp.SHAPE) and bp.admincode='' AND c.admincode =$admincode) a
			where bup.polygon_id=a.id\""
    sql_d="\"Select d.shape, d.AdminCode, d.Kind FROM d d where d.admincode like '$provadcode%'\""
    #建筑数据
    #sql_building="\"SELECT b.* FROM building b, admarea_city c WHERE ST_Intersects(c.SHAPE, b.SHAPE) AND c.admincode =$admincode\""
    #道路数据
    sql_r="\"SELECT r.shape, r.MapID, r.id, r.Kind_num, r.Kind, r.width, r.Direction, r.Toll, r.Const_St, r.UndConCRID, r.SnodeID, r.EnodeID, 
			r.FuncClass, r.Length, r.DetailCity, r.Through, r.UnThruCRID, r.Ownership, r.Road_Cond, r.Special, r.AdminCodeL, r.AdminCodeR, 
			r.Uflag, r.OnewayCRID, r.AccessCRID, r.SpeedClass, r.LaneNumS2E, r.LaneNumE2S, r.LaneNum, r.Vehcl_Type, r.Elevated, r.Structure, 
			r.UseFeeCRID, r.UseFeeType, r.SpdLmtS2E, r.SpdLmtE2S, r.SpdSrcS2E, r.SpdSrcE2S, r.DC_Type, r.NoPassCRID FROM r r, admarea_city c 
			WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode\""
    sql_rlname="\"SELECT n.MapID, n.id, n.Route_ID, n.Name_Kind, n.Name_Type, n.Seq_Nm FROM r_lname n join r r on r.id=n.id join admarea_city c on ST_Intersects(c.SHAPE, r.SHAPE) where c.admincode =$admincode\""
    sql_rname="\"Select n.Route_ID, n.Route_Kind, n.PathName, n.PathPY, n.PreName, n.PrePY, n.BaseName, n.BasePY, n.StTpName, n.StTpPY, n.SurName, 
			n.SurPY, n.WavName, n.Language, n.StTpLoc FROM r_name n join r_lname lname on n.route_id=lname.route_id join r r on lname.id=r.id join admarea_city c on ST_Intersects(c.SHAPE, r.SHAPE) where c.admincode =$admincode\""
    sql_rlzone="\"Select l.MapID, l.id, l.ZoneID, l.Side, l.ZType from r_lzone l join r r on l.id=r.id join admarea_city c on ST_Intersects( c.SHAPE, r.SHAPE ) where c.admincode =$admincode\""
    sql_n="\"Select n.shape, n.MapID, n.id, n.Kind_num, n.Kind, n.Cross_flag, n.Light_flag, n.Cross_LID, n.mainNodeID, n.subNodeID, n.subNodeID2,
			n.Adjoin_MID, n.Adjoin_NID, n.Node_LID FROM n n, admarea_city c WHERE ST_Intersects(c.SHAPE, n.SHAPE) AND c.admincode =$admincode\""
    sql_c="\"Select c.shape, c.MapID, c.CondID, c.id, c.inLinkID, c.outLinkID, c.CondType, c.CRID, c.Passage, c.Slope, c.SGNL_LOCTION FROM c c, admarea_city adm WHERE ST_Intersects(adm.SHAPE, c.SHAPE) AND adm.admincode =$admincode\""
    sql_cond="\"Select cond.MapID, cond.CondID, cond.CondType, cond.CRID, cond.Passage, cond.Slope, cond.SGNL_LOCTION 
			FROM cond cond,(SELECT distinct r.mapid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode=$admincode) a
			where cond.mapid=a.mapid\""
    sql_cnl="\"Select cnl.MapID, cnl.CondID, cnl.LinkID, cnl.NodeID, cnl.Seq_Nm, cnl.Angle
			FROM cnl cnl,(SELECT distinct r.mapid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode=$admincode) a
			where cnl.mapid=a.mapid\""
    sql_cr="\"Select cr.CRID, cr.VPeriod, cr.VPDir, cr.Vehcl_Type, cr.VP_Approx FROM cr cr join c c on cr.crid=c.crid join admarea_city adm on ST_Intersects(adm.SHAPE, c.SHAPE) 
			where adm.admincode=$admincode
			union
			Select cr.CRID, cr.VPeriod, cr.VPDir, cr.Vehcl_Type, cr.VP_Approx FROM cr cr ,(
                SELECT r.UndConCRID crid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode
                union
                SELECT r.UnThruCRID crid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode
                union
                SELECT r.OnewayCRID crid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode
                union
                SELECT r.AccessCRID crid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode
                union
                SELECT r.UseFeeCRID crid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode
                union
                SELECT r.NoPassCRID crid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode
                union
                SELECT cond.CRID crid FROM cond cond,(SELECT distinct r.mapid FROM r r, admarea_city c WHERE ST_Intersects(c.SHAPE, r.SHAPE) AND c.admincode =$admincode) a where cond.mapid=a.mapid
                union
                SELECT s.CRID crid FROM special_speed s join r r on r.id=s.id join admarea_city c on ST_Intersects(c.SHAPE, r.SHAPE) where c.admincode =$admincode
                union
                SELECT t.CRID crid FROM trfcsign t join r r on t.mapid=r.mapid join admarea_city c on ST_Intersects( c.SHAPE, r.SHAPE ) where c.admincode =$admincode
            ) a where a.crid=cr.crid\""
    sql_ss="\"Select s.MapID, s.ID, s.Type, s.SpeedLimit, s.Dependent, s.CRID FROM special_speed s join r r on r.id=s.id join admarea_city adm on ST_Intersects(adm.SHAPE, r.SHAPE) where adm.admincode =$admincode\""
    sql_ic="\"Select i.shape, i.MapID, i.id, i.NodeID, i.inLinkID, i.outLinkID, i.WavName, i.PassLid FROM ic i, admarea_city c WHERE ST_Intersects(c.SHAPE, i.SHAPE) AND c.admincode =$admincode\""
    sql_dr="\"Select d.shape, d.MapID, d.id, d.NodeID, d.inLinkID, d.outLinkID, d.WavName, d.PassLid, d.PassLid2, d.type FROM dr d, admarea_city c WHERE ST_Intersects(c.SHAPE, d.SHAPE) AND c.admincode =$admincode\""
    sql_zl="\"Select z.shape, z.MapID, z.id, z.Seq_Nm, z.Z, z.LinkType, z.Level_ID FROM z_level z, admarea_city c WHERE ST_Intersects(c.SHAPE, z.SHAPE) AND c.admincode =$admincode\""
    sql_trfc="\"Select t.MapID, t.inLinkID, t.NodeID, t.type, t.ValidDist, t.PreDist, t.CRID FROM trfcsign t join r r on t.mapid=r.mapid join admarea_city c on ST_Intersects( c.SHAPE, r.SHAPE ) where c.admincode =$admincode\""
    sql_ln="\"Select l.shape, l.MapID, l.NodeID, l.inLinkID, l.outLinkID, l.LaneNum, l.LaneInfo, l.ArrowInfo, l.LaneNumL, l.LaneNumR, l.PassLid, 
			l.PassLid2, l.BusLane FROM ln l, admarea_city c WHERE ST_Intersects(c.SHAPE, l.SHAPE) AND c.admincode=$admincode\""
    #文本数据
    exec_export "$sql_t"  "T" 2
    #索引数据
    exec_export "$sql_poi"  "POI" 5
    exec_export "$sql_pr"  "POI_Relation" 8
    exec_export "$sql_hamlet"  "Hamlet" 11
    exec_export "$sql_z"  "Z" 15
    exec_export "$sql_a"  "A" 20
    exec_export "$sql_ac"  "AC" 25
    #other数据
    exec_export "$sql_admin"  "Admin" 30
    exec_export "$sql_pname"  "PName" 33
    exec_export "$sql_hmname"  "HmName" 35
	exec_export "$sql_fname"  "FName" 37
    #背景数据
    exec_export "$sql_bn"  "BN" 39
    exec_export "$sql_bl"  "BL" 41
    exec_export "$sql_bp"  "BP" 43
    exec_export "$sql_bpl"  "BPL" 45
    exec_export "$sql_bup"  "BUP" 47
    exec_export "$sql_d"  "D" 49
    #建筑数据
    #exec_export "$sql_building" "building" "$admincode"  "$sourcename" $uuid
    #道路数据
    exec_export "$sql_r"  "R" 51
    exec_export "$sql_rlname"  R_LName 53
    exec_export "$sql_rname"  R_Name 55
    exec_export "$sql_rlzone"  R_LZone 58
    exec_export "$sql_n" N  60
    exec_export "$sql_c"  C 65
    exec_export "$sql_cond"  Cond 70
    exec_export "$sql_cnl"  CNL 73
    exec_export "$sql_cr" CR 76
    exec_export "$sql_ss" Special_Speed 80
    exec_export "$sql_ic"  IC 83
    exec_export "$sql_dr"  Dr 85
    exec_export "$sql_zl" Z_Level 88
    exec_export "$sql_trfc" TrfcSign 91
    exec_export "$sql_ln"  Ln 95
    exec_url  "all"
}

function export_gd_poi(){
    admincode="'$admincode'"
    sql_add="\"SELECT b.* FROM poi_add_20131202 b, admarea_city c WHERE c.admincode =$admincode AND b.city = c.cityname\""
    sql_same="\"SELECT b.* FROM poi_same_20131202 b, admarea_city c WHERE c.admincode =$admincode AND b.city = c.cityname\""
    sql_up="\"SELECT b.* FROM poi_up_20131202 b, admarea_city c WHERE c.admincode =$admincode AND b.city = c.cityname\""

    exec_export "$sql_add" "gd_poi_add" 33
    exec_export "$sql_same" "gd_poi_same" 67
    exec_export "$sql_up" "gd_poi_up" 95
    exec_url "gd_poi"
}

function insert_taskinfo(){
	zippath=$filepath/${admpy}.zip
	cmd="mysql -h ${mysql_config} -P${mysql_config_port} -u${mysql_config_user} -p${mysql_config_password} ${mysql_config_db} -e \"insert into task_info_replace(task_id,name,admincode,datasource,datainfo,filetype,proj,filepath) VALUES('$taskid','${taskname}','${admincode}',$sourcename,$typename,'MIF','国测局','$zippath')\""
	bash -c "$cmd"
}

function copy_taskinfo(){
    cmd="mysql -h ${mysql_config} -P${mysql_config_port} -u${mysql_config_user} -p${mysql_config_password} ${mysql_config_db} -e \"insert into task_info_replace(task_id,name,admincode,datasource,datainfo,url,progress,status,filetype,proj,filepath) VALUES('$taskid','${taskname}','${admincode}',$sourcename,$typename,$1,100,1,'MIF','国测局',$2)\""
    bash -c "$cmd"
}

function update_taskinfo(){
	cmd="mysql -h ${mysql_config} -P${mysql_config_port} -u${mysql_config_user} -p${mysql_config_password} ${mysql_config_db} -e \"update task_info_replace set $1=$2 where task_id='$taskid'\""
	bash -c "$cmd"
}

function get_admpy(){
	cmd="mysql -N -s -h ${mysql_config} -P${mysql_config_port} -u${mysql_config_user} -p${mysql_config_password} ${mysql_config_db} -e \"select CONCAT(pro_name,'.',pro_py,'.',city_name,'.',city_ename) from admcity_ll where admincode='$admincode'\" 2>/dev/null"
	admpy=`eval $cmd`
	admpy=${admpy// /}
	admpy=`tr '[A-Z]' '[a-z]' <<<"$admpy"`
	admpy=${admpy%shi}
	echo $admpy
}

function get_existsTask(){
	cmd="mysql -N -s -h ${mysql_config} -P${mysql_config_port} -u${mysql_config_user} -p${mysql_config_password} ${mysql_config_db} -e \"select CONCAT(url,'|',filepath) from task_info_replace where progress=100 and admincode=$admincode and datasource=$sourcename and datainfo=$typename limit 1\" 2>/dev/null"
	admpy=`eval $cmd`
	echo $admpy
}

if [ $# -eq 0 ]
then
    usage
    fail "argv error"
fi

while getopts "d:f:a:i:" optname
do
    case "$optname" in
    "d")
        sourcename=$OPTARG
        ;;
    "f")
        typename=$OPTARG
        ;;
    "a")
        admincode=$OPTARG
        ;;
    "i")
        taskid=$OPTARG
        ;;
    "?")
        echo "Unkown option $OPTARG"
        ;;
    *)
        echo "Unkown error while processing options"
        ;;
    esac
done

if [ -z "$sourcename" ]
then
    fail "please input data source name"
fi

if [ -z "$typename" ]
then
    fail "please input data type"
fi

if [ -z "$admincode" ]
then
    fail "please input admincode"
fi

if [ -z "$taskid" ]
then
    fail "please input taskid"
fi

RET=`expr match $admincode "[0-9]*$"`
if [ ${RET} -gt 0 ]; then
  RET=0
else
  fail "not a admincode !"
fi

init_check ogr2ogr mysql


str=$(get_admpy)
str=${str//./ }
arr=($str)
admprov=${arr[0]}
admprovpy=${arr[1]}
admcity=${arr[2]}

taskname=$admprov$admcity
admpy=${arr[3]}
admpy=${admpy//\'/}
if [[ $sourcename = "1" ]]; then
    version=$ver_sw
else
    if [[ $typename = "1" ]]; then
        version=$ver_gd_road
    elif [[ $typename = "4" ]]; then
        version=$ver_gd_poi
	else
		version='2013'
    fi
fi
replace_path='replace'/${sourcename}/${typename}/${version}/${admprovpy}/${admpy}
uuid=$(get_uuid)
filepath=${web_storage_root}/${replace_path}
echo $filepath

taskinfo=$(get_existsTask)
if [ ! -z $taskinfo ]; then
    str=${taskinfo//|/ }
    arr=($str)
    url_e=${arr[0]}
    path_e=${arr[1]}
    
    path_e=${path_e/#$web_storage_root/$net_storage_root}
    
    filename=${path_e##*/}
    localpath=${filepath}/${filename}
    echo $localpath
    if [ ! -f "$localpath" ]; then
        create_dir $filepath
        cp -rf $path_e $filepath
        echo 'copy file from net system'
    fi
    
    `cd ${filepath};unzip -o ${filename}`
	exec_stacheck
    echo 'process delete MIF...'
    copy_taskinfo "'$url_e'" "'$localpath'"
    `cd ${filepath};rm -f *.mif *.mid`
    suc "${url_e}"
    exit 0
fi

case  "$typename" in
    "0")
        insert_taskinfo
        export_all
        ;;
    "1")
        if [[ $sourcename = "2" ]]; then
            insert_taskinfo
            export_road
            if [[ $? -eq 1 ]]; then
                fail  " no data now"
            fi
        fi
		insert_taskinfo
        export_road
        ;;
    "2")
        if [[ $sourcename = "2" ]]; then
        fail  " no data now"  
        fi
		insert_taskinfo
        export_bg
        ;;
    "3")
		insert_taskinfo
        export_building
        ;;
    "4")
        if [[ $sourcename = "1" ]]; then
        fail  " no data now"  
        fi
        insert_taskinfo
        export_gd_poi
        ;;
    *)
		fail "typename error"
		exit 1
		;;
esac



