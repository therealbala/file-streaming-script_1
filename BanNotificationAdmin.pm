package Engine::Cronjobs::BanNotificationAdmin;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   my ($period_check) = @_;
   return if !$c->{max_login_attempts_h} && !$c->{max_login_ips_h};
   return if !$period_check->(24 * 60);

   my $bans = $db->SelectARef("SELECT *, ip AS ip2 FROM Bans
                     WHERE created > NOW() - INTERVAL 24 HOUR");
   for(@$bans) {
      $_->{usr_login} = $db->SelectOne("SELECT usr_login FROM Users WHERE usr_id=?", $_->{usr_id});
      $_->{usr_login} =~ s/[<>]//g;
   }

   my @bans_users = grep { $_->{usr_id} } @$bans;
   my @bans_ips = grep { $_->{ip} } @$bans;
   if(@bans_ips || @bans_users) {
	   my $tmpl = $ses->CreateTemplate("ban_notification_admin.html");
      $tmpl->param(
                  bans_ips => \@bans_ips,
                  bans_users => \@bans_users,
                  site_url => $c->{site_url},
                  );
      $ses->SendMail( $c->{contact_email}, $c->{email_from}, "$c->{site_name}: Security report", $tmpl->output() );
   }
}

1;
