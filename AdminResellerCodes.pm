package Engine::Actions::AdminResellerCodes;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my $key = $f->{key} if $f->{key};
   my $filter_key = "AND CONCAT(key_id, key_code) = '$key'" if $key;

   my $list = $db->SelectARef("SELECT *,
         r.usr_id AS reseller_id,
         r.usr_login AS reseller_login,
         u.usr_id AS buyer_id,
         u.usr_login AS buyer_login
      FROM PremiumKeys k
      LEFT JOIN Users r ON r.usr_id = k.usr_id
      LEFT JOIN Users u ON u.usr_id = k.usr_id_activated
      WHERE 1
      $filter_key
      ORDER BY key_created DESC"
      .$ses->makePagingSQLSuffix($f->{page}));

   my $total = $db->SelectOne("SELECT COUNT(*) FROM PremiumKeys WHERE 1 $filter_key");

   return $ses->PrintTemplate("admin_reseller_codes.html",
      list => $list,
      key => $f->{key},
      paging => $ses->makePagingLinks($f,$total));
}

1;
