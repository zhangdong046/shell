<?php
function judge_poi_result($name)
{
	exec("./check.sh  $name> /dev/null 2>&1");
	$file='./data/tmp.log';
	$result=false;
	$content=file_get_contents($file);
	if($content!=null)
	{
		$result=true;
	}
	return $result;
}
?>
