package Engine::Actions::CheckCode;
use strict;

use XFileConfig;
use Engine::Core::Action;
use XUtils;

sub main
{
   return $ses->PrintJSON({ result => XUtils::CheckCode($f) ? 'OK' : 'INVALID' });
}


1;
