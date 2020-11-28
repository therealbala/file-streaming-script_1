package Engine::Actions::EmailUnsubscribe;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my $user = $db->SelectRow( "SELECT * FROM Users WHERE usr_id=? AND usr_email=?", $f->{id}, $f->{email} );
   return $ses->message($ses->{lang}->{lang_invalid_unsubscription_link}) unless $user;
   $db->Exec( "UPDATE Users SET usr_no_emails=1 WHERE usr_id=?", $user->{usr_id} );
   return $ses->message($ses->{lang}->{lang_successfully_unsubscribed});
}

1;
