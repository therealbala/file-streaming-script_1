package Engine::Actions::AdminUsersAdd;
use strict;

use XFileConfig;
use Engine::Core::Action;

use XUtils;

sub main
{
   my ( $list, $result );
   my $usersRegistry = $ses->require("Engine::Components::UsersRegistry");

   if ( $f->{generate} )
   {
      my @arr;
      $f->{prem_days} ||= 0;
      for ( 1 .. $f->{num} )
      {
         push @arr, join(":", $usersRegistry->randomLogin(), $ses->randchar(10), $f->{prem_days});
      }
      $list = join "\n", @arr;
   }
   if ( $f->{create} && $f->{list} )
   {
      my @arr;
      $f->{list} =~ s/\r//gs;
      for ( split /\n/, $f->{list} )
      {
         return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
         my ( $login, $password, $days, $email ) = split( /:/, $_ );
         next unless $login =~ /^[\w\-\_]+$/ && $password =~ /^[\w\-\_]+$/;
         $days =~ s/\D+//g;
         $days ||= 0;

         push( @arr, "<b>$login:$password:$days - ERROR:login already exist</b>" ), next
           if $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_login=?", $login );

         $usersRegistry->createUser({
            login => $login,
            password => $password,
            premium_days => $days,
            email => $email,
         });

         push @arr, "$login:$password:$days";
      }
      $result = join "<br>", @arr;
   }
   $ses->PrintTemplate(
      "admin_users_add.html",
      'list'   => $list,
      'result' => $result,
   );
}

1;
