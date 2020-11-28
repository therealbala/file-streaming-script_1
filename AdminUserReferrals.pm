package Engine::Actions::AdminUserReferrals;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my $referrals = $db->SelectARef(
      "SELECT usr_id,usr_login,usr_created,usr_money,usr_aff_id 
                                     FROM Users 
                                     WHERE usr_aff_id=? 
                                     ORDER BY usr_created DESC 
                                     " . $ses->makePagingSQLSuffix( $f->{page} ), $f->{usr_id}
   );
   my $total = $db->SelectOne( "SELECT COUNT(*) FROM Users WHERE usr_aff_id=?", $f->{usr_id} );
   my $user = $db->SelectRow( "SELECT usr_id,usr_login FROM Users WHERE usr_id=?", $f->{usr_id} );
   $ses->PrintTemplate(
      "admin_user_referrals.html",
      referrals => $referrals,
      'paging'  => $ses->makePagingLinks( $f, $total ),
      %{$user},
   );
}

1;
