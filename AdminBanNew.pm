package Engine::Actions::AdminBanNew;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(save)] );

sub main
{
   return $ses->PrintTemplate("admin_ban_new.html");
}

sub save
{
   $db->Exec("INSERT IGNORE INTO Bans SET ip=?, reason=?",
      $f->{ip},
      $f->{reason});
   return $ses->redirect_msg("$c->{site_url}/?op=admin_bans_list", "IP successfully added");
}

1;
