package Engine::Actions::Logout;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   return $ses->Logout();
}

1;
