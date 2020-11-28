package Engine::Actions::ForgotPass;
use strict;

use XFileConfig;
use Engine::Core::Action (
   'IMPLEMENTS' => [qw(sess usr_login)],
   'ANTICSRF_WHITELIST' => ['sess', 'usr_login']
);

sub main
{
   $ses->setCaptchaMode( $c->{captcha_mode} || 2 );
   return $ses->redirect( $c->{site_url} ) if $ses->getUser;

   $f->{usr_login} = $ses->SecureStr( $f->{usr_login} );
   my %secure = $ses->SecSave( 0, 0 );
   $ses->PrintTemplate( "forgot_pass.html", %{$f}, %secure, );
}

sub sess
{
   my $session = $db->SelectRow(
      "SELECT * FROM Sessions
                      WHERE session_id=?", $f->{sess}
   );
   return $ses->message("Wrong session") if !$session;
   my $user = $db->SelectRow( "SELECT * FROM Users WHERE usr_id=?", $session->{usr_id} );
   $db->Exec( "DELETE FROM Sessions WHERE usr_id=?", $user->{usr_id} );
   if ( $user->{usr_security_lock} )
   {
      return $ses->message("Error: security code doesn't match")
        if $f->{code} ne $user->{usr_security_lock};
      $db->Exec( "UPDATE Users SET usr_security_lock='' WHERE usr_id=?", $user->{usr_id} );
   }
   my $new_sess_id = $ses->randchar(16);
   $db->Exec( "UPDATE Sessions SET session_id=? WHERE usr_id=?",                       $new_sess_id, $session->{usr_id} );
   $db->Exec( "INSERT INTO Sessions (session_id,usr_id,last_time,last_ip) VALUES (?,?,NOW(),?)", $new_sess_id, $session->{usr_id}, $ses->getIP );
   $ses->setCookie( $ses->{auth_cook}, $new_sess_id, '+30d' );
   $db->Exec( "UPDATE Users SET usr_password='', usr_security_lock='' WHERE usr_id=?", $user->{usr_id} );
   $db->Exec( "UPDATE Users SET usr_status='OK' WHERE usr_id=?", $user->{usr_id} ) if $user->{usr_status} eq 'PENDING';
   return $ses->redirect( $c->{site_url} );
}

sub usr_login
{
   $ses->setCaptchaMode( $c->{captcha_mode} || 2 );

   return main() if !$ses->SecCheck($f->{'rand'}, 0, $f->{code});

   my $user = $db->SelectRow(
      "SELECT * FROM Users 
                                 WHERE (usr_login=? 
                                 OR usr_email=?)",
      $f->{usr_login},
      $f->{usr_login}
   );
   return $ses->message( $ses->{lang}->{lang_no_login_email} ) unless $user;
   my $sess_id = $ses->randchar(16);
   $db->Exec( "INSERT INTO Sessions (session_id,usr_id,last_time) VALUES (?,?,NOW())", $sess_id, $user->{usr_id} );
   my $token = $ses->genToken();
   my $link = "$c->{site_url}/?op=forgot_pass&sess=$sess_id&token=$token";
   $link .= "&code=$user->{usr_security_lock}" if $user->{usr_security_lock};
   $ses->SendMail(
      $user->{usr_email}, $c->{email_from},
      "$c->{site_name}: password recovery",
      "Please follow this link to continue recovery:\n<a href=\"$link\">$link</a>"
   );
   return $ses->PrintTemplate(
      "message.html",
      err_title => "Notice",
      msg       => "Password recovery link sent to your e-mail"
   );
}

1;
