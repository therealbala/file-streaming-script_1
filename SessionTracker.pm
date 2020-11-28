package Engine::Components::SessionTracker;
use strict;
use vars qw($ses $db $c $f);

sub StartSession
{
   my ($self, $usr_id) = @_;
   my $sess_id = $ses->randchar(16);
   $db->Exec("DELETE FROM Sessions WHERE last_time + INTERVAL 5 DAY < NOW()");
   $db->Exec("INSERT INTO Sessions (session_id,usr_id,last_ip,last_useragent,last_time) VALUES (?,?,?,?,NOW())",
      $sess_id,$usr_id,$ses->getIP,$ses->getEnv('HTTP_USER_AGENT')||'');
   $db->Exec("UPDATE Users SET usr_lastlogin=NOW(), usr_lastip=? WHERE usr_id=?", $ses->getIP, $usr_id);
   return $sess_id;
}

sub GetSession
{
   my ($self, $usr_id) = @_;
   my $session = $db->SelectRow("SELECT * FROM Sessions WHERE usr_id=?", $usr_id);
   return $session ? $session->{session_id} : $self->StartSession($usr_id);
}

1;
