package Engine::Actions::AdminMassEmail;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(send)] );

use XUtils;

sub main
{

   my @users = map { { usr_id => $_ } } @{ XUtils::ARef( $f->{usr_id} ) };
   $ses->PrintTemplate(
      "admin_mass_email.html",
      users     => \@users,
      users_num => scalar @users,
      token_mass_email => $ses->genToken( op => 'admin_mass_email' ),
   );
}

sub send
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   return $ses->message($ses->{lang}->{lang_subject_required}) unless $f->{subject};
   return $ses->message($ses->{lang}->{lang_message_required}) unless $f->{body};

   my @filters = XUtils::UserFilters($f);
   push @filters, "AND usr_id IN (" . join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{usr_id} ) } ) . ")" if $f->{usr_id};
   push @filters, "AND usr_no_emails=0" if !$f->{usr_id};
   my $filters = join(" ", @filters);

   my $users = $db->SelectARef(
      "SELECT usr_id,usr_login,usr_email 
                                   FROM Users 
                                   WHERE 1
                                   $filters");

   $|++;

   print "Content-type:text/html\n\n<HTML><BODY>";
   my $cx;

   #die $#$users;
   for my $u (@$users)
   {
      next unless $u->{usr_email};
      my $body = $f->{body};
      $body =~ s/%username%/$u->{usr_login}/egis;
      $body =~ s/%unsubscribe_url%/"$c->{site_url}\/?op=email_unsubscribe&id=$u->{usr_id}&email=$u->{usr_email}"/egis;
      $ses->SendMail( $u->{usr_email}, $c->{email_from}, $f->{subject}, $ses->UnsecureStr($body) );
      print "Sent to $u->{usr_email}<br>\n";
      $cx++;
   }
   print "<b>DONE.</b><br><br>Sent to <b>$cx</b> users.<br><br><a href='?op=admin_users'>Back to User Management</a>";
   return;
}

1;
