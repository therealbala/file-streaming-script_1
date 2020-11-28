package Engine::Components::TokenRegistry;
use strict;
use vars qw($ses $db $c $f);

my $LAST_ERROR;

sub _check(\%\@\@)
{
   my ($opts, $required, $defined) = @_;
   my %valid = map { $_ => 1 } (@$required, @$defined);

   my ($pkg, $fn, $ln) = caller(1);
   for(@$required) { die("Required option: $_ at $fn:$ln\n") if !defined($opts->{$_}); }
   for(keys %$opts) { die("Unknown option: $_ at $fn:$ln\n") if !$valid{$_}; }
}

sub createToken
{
   my ($self, $opts) = @_;

   my @required = qw(purpose);
   my @defined = qw(phone usr_id length); 
   _check(%$opts, @required, @defined);

   my $usr_id = $ses->getUser ? $ses->getUserId : 0;
   my $secret_code = $ses->randchar($opts->{length}||16);
   $db->Exec("INSERT INTO SecurityTokens SET usr_id=?, purpose=?, ip=?, value=?, phone=?",
      $opts->{usr_id}||$usr_id, $opts->{purpose}, $ses->getIP, $secret_code, $opts->{phone}||'');
   return $secret_code;
}

sub sendSMSToken
{
   my ($self, $opts) = @_;
   $LAST_ERROR = '';

   my @required = qw(purpose phone);
   my @defined = qw(usr_id); 

   my $secret_code = $self->createToken({ %$opts, length => 8 });
   return error("Error while sending SMS: $ses->{errstr}")
      if !$ses->SendSMS( $opts->{phone}, "$c->{site_name} $opts->{purpose} confirmation code: $secret_code" );
   return $secret_code;
}

sub checkToken
{
   my ($self, $opts) = @_;
   my @required = qw(purpose code);
   my @defined = qw(phone usr_id); 
   _check(%$opts, @required, @defined);

   my $usr_id = $ses->getUser ? $ses->getUserId : 0;
   my $token = $db->SelectRow("SELECT * FROM SecurityTokens WHERE usr_id=? AND purpose=? AND value=?",
      $opts->{usr_id}||$usr_id, $opts->{purpose}, $opts->{code});

   if($token)
   {
      $db->Exec("DELETE FROM SecurityTokens WHERE id=?", $token->{id});
      return 1;
   }
}

sub lastError
{
   return $LAST_ERROR;
}

sub error
{
   my ($error) = @_;
   $LAST_ERROR = $error;
}

1;
