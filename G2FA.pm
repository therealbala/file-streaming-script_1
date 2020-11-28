package Engine::Components::G2FA;
use strict;
use vars qw($ses $db $c $f);
use Auth::GoogleAuth;

sub verify
{
   my ($self, $secret32, $code6) = @_;
   my $auth = Auth::GoogleAuth->new;
   return $auth->verify($code6, 1, $secret32, time(), 30);
}

1;
