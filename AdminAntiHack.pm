package Engine::Actions::AdminAntiHack;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my $gen_ip = $db->SelectARef(
      "SELECT ip as ip_txt, SUM(money) as money, COUNT(*) as downloads
                                 FROM IP2Files 
                                 WHERE created>NOW()-INTERVAL 48 HOUR
                                 GROUP BY ip
                                 ORDER BY money DESC
                                 LIMIT 20"
   );

   my $gen_user = $db->SelectARef(
      "SELECT u.usr_login, u.usr_id, SUM(money) as money, COUNT(*) as downloads
                                 FROM IP2Files i, Users u
                                 WHERE created>NOW()-INTERVAL 48 HOUR
                                 AND i.usr_id=u.usr_id
                                 GROUP BY i.usr_id
                                 ORDER BY money DESC
                                 LIMIT 20"
   );

   my $rec_user = $db->SelectARef(
      "SELECT u.usr_login, u.usr_id, SUM(money) as money, COUNT(*) as downloads
                                 FROM IP2Files i, Users u
                                 WHERE created>NOW()-INTERVAL 48 HOUR
                                 AND i.owner_id=u.usr_id
                                 GROUP BY i.owner_id
                                 ORDER BY money DESC
                                 LIMIT 20"
   );

   $ses->PrintTemplate(
      "admin_anti_hack.html",
      'gen_ip'          => $gen_ip,
      'gen_user'        => $gen_user,
      'rec_user'        => $rec_user,
      'currency_symbol' => ( $c->{currency_symbol} || '$' ),
   );
}

1;
