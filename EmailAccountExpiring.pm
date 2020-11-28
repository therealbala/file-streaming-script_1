package Engine::Cronjobs::EmailAccountExpiring;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   my ($period_check) = @_;
   return if !$period_check->(24 * 60);

   my $users_expiring = $db->SelectARef("SELECT usr_login,usr_email 
                                         FROM Users 
                                         WHERE usr_premium_expire>NOW()
                                         AND usr_premium_expire<NOW()+INTERVAL 48 HOUR");

   for my $user (@$users_expiring)
   {
      my $t = $ses->CreateTemplate("email_account_expiring.html");
      $t->param(%$user);
      print"Sending account expire email to $user->{usr_login} ($user->{usr_email})\n";
      $ses->SendMail( $user->{usr_email}, $c->{email_from}, "$c->{site_name}: your Premium account expiring soon", $t->output );
   }
}

1;
