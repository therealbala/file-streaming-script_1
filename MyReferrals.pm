package Engine::Actions::MyReferrals;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my $list = $db->SelectARef(
      "SELECT usr_login, usr_created, usr_money, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as dt
                               FROM Users WHERE usr_aff_id=? ORDER BY usr_created DESC"
        . $ses->makePagingSQLSuffix( $f->{page} ), $ses->getUserId
   );
   my $total = $db->SelectOne( "SELECT COUNT(*) FROM Users WHERE usr_aff_id=?", $ses->getUserId );
   for (@$list)
   {
      $_->{prem} = 1 if $_->{dt} > 0;
      $_->{usr_money} =~ s/\.?0+$//;
   }
   $ses->PrintTemplate(
      "my_referrals.html",
      list              => $list,
      paging            => $ses->makePagingLinks( $f, $total ),
      'currency_symbol' => ( $c->{currency_symbol} || '$' ),
   );
}

1;
