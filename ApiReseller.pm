package Engine::Actions::ApiReseller;
use strict;
use XUtils;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my %opts = (disable_login_ips_check => 1, disable_2fa_check => 1);
   my $user = $ses->require("Engine::Components::Auth")->checkLoginPass($f->{u}, $f->{p}, %opts);

   print "Content-type:text/html\n\n";
   print("ERROR:Reseller mod disabled"),     return unless $c->{m_k};
   print("ERROR:Invalid username/password"), return if !$user || ($c->{m_k_manual} && !$user->{usr_reseller});

   $f->{t} = lc $f->{t};
   my $price;
   for ( split( /,/, $c->{m_k_plans} ) )
   {
      my ( $pr, $time ) = /^(.+)=(.+)$/;
      $price = $pr if $time eq $f->{t};
   }

   print("ERROR:Invalid time"), return unless $price;
   print("ERROR:Not enough money"), return if $user->{usr_money} < $price;

   my @r        = ( 'a' .. 'z' );
   my $key_code = $r[ rand scalar @r ] . $ses->randchar(13);
   $db->Exec( "INSERT INTO PremiumKeys SET usr_id=?, key_code=?, key_time=?, key_price=?, key_created=NOW()",
      $user->{usr_id}, $key_code, $f->{t}, $price );
   my $id = $db->getLastInsertId;
   $db->Exec( "UPDATE Users SET usr_money=usr_money-? WHERE usr_id=?", $price, $user->{usr_id} );
   print "$id$key_code";
   return;
}

1;
