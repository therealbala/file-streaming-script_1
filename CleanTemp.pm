package Engine::Cronjobs::CleanTemp;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

use XUtils;

sub main
{
   XUtils::MapFileServers($ses, { op => 'expire_temp', hours => 24 }, "Deleting temp files");
}

1;
