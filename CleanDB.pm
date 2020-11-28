package Engine::Cronjobs::CleanDB;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   print "Cleaning old DB records...<br>\n";

   $db->Exec("DELETE FROM Reports WHERE created<NOW() - INTERVAL 3 MONTH");
   $db->Exec("DELETE FROM IP2RS WHERE created<NOW() - INTERVAL 7 DAY");
   $db->Exec( "DELETE FROM Sessions WHERE last_time<NOW() - INTERVAL ? HOUR", ( $c->{mod_sec_delete_sessions_after} || 72 ) );

   $db->Exec("DELETE FROM DelReasons WHERE last_access<NOW() - INTERVAL 6 MONTH");
   $db->Exec("DELETE FROM LoginProtect where created < NOW() - INTERVAL 1 HOUR");
   $db->Exec("DELETE FROM SecurityTokens where created < NOW() - INTERVAL 30 MINUTE");
   $db->Exec("DELETE FROM DownloadTokens WHERE created <= NOW() - INTERVAL ? HOUR", $c->{token_links_expiry}) if $c->{token_links_expiry};

   $db->Exec( "DELETE FROM IP2Files WHERE created<NOW() - INTERVAL ? DAY LIMIT 5000", $c->{clean_ip2files_days} )
     if $c->{clean_ip2files_days};
}

1;
