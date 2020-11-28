package Engine::Actions::Contact;
use strict;

use XFileConfig;
use Engine::Core::Action(IMPLEMENTS => [qw(send)]);

sub main
{
   $ses->setCaptchaMode( $c->{captcha_mode} || 2 );
   my %secure = $ses->SecSave(1);
   $f->{$_} = $ses->SecureStr( $f->{$_} ) for keys %$f;
   $f->{email} ||= $ses->getUser->{usr_email} if $ses->getUser;
   $ses->PrintTemplate( "contact.html", %{$f}, %secure, );
}

sub send
{
   $ses->setCaptchaMode( $c->{captcha_mode} || 2 );
   return &main() unless $ses->getEnv('REQUEST_METHOD') eq 'POST';
   return &main() unless $ses->SecCheck( $f->{'rand'}, 1, $f->{code} );

   $f->{msg} .= "Email is not valid. " unless $f->{email} =~ /^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
   $f->{msg} .= "Message required. " unless $f->{message};

   return &main() if $f->{msg};

   my $ip = $ses->getIP;

   $f->{message} =
"You've got new message from $c->{site_name}.\n\nName: $f->{name}\nE-mail: $f->{email}\nIP: $ip\n\n$f->{message}";
   $c->{email_text} = 1;
   $ses->SendMail( $c->{contact_email}, $c->{email_from}, "New message from $c->{site_name} contact form", $ses->UnsecureStr($f->{message}) );
   return $ses->redirect("$c->{site_url}/?msg=Message sent successfully");
}

1;
