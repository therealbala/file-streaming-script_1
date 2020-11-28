package Engine::Components::UsersRegistry;
use strict;
use vars qw($ses $db $c $f);
use XUtils;

sub _check(\%\@\@)
{
   my ($opts, $required, $defined) = @_;
   my %valid = map { $_ => 1 } (@$required, @$defined);

   my ($pkg, $fn, $ln) = caller(1);
   for(@$required) { die("Required option: $_ at $fn:$ln\n") if !defined($opts->{$_}); }
   for(keys %$opts) { die("Unknown option: $_ at $fn:$ln\n") if !$valid{$_}; }
}

sub createUser
{
   my ($class, $opts) = @_;
   my @required = qw(login);
   my @defined = qw(email password premium_days security_lock status aff_id pay_email pay_type profit_mode notes phone social social_id);
   _check(%$opts, @required, @defined);

   my $passwd_hash = XUtils::GenPasswdHash($opts->{password}) if $opts->{password};

   $db->Exec(
      "INSERT INTO Users 
              SET usr_login=?, 
                  usr_email=?, 
                  usr_password=?,
                  usr_created=NOW(),
                  usr_premium_expire=NOW()+INTERVAL ? DAY,
                  usr_security_lock=?,
                  usr_status=?,
                  usr_aff_id=?,
                  usr_pay_email=?, 
                  usr_pay_type=?,
                  usr_profit_mode=?,
                  usr_notes=?,
                  usr_phone=?,
                  usr_social=?,
                  usr_social_id=?,
                  usr_no_emails=?",
      $opts->{login},
      $opts->{email}||'',
      $passwd_hash,
      $opts->{premium_days}||0,
      $opts->{security_lock}||'',
      $opts->{status}||'OK',
      $opts->{aff_id}||0,
      $opts->{pay_email}||'',
      $opts->{pay_type}||'',
      $opts->{profit_mode}||$c->{m_y_default}||'PPD',
      $opts->{notes}||'',
      $opts->{phone}||'',
      $opts->{social}||'',
      $opts->{social_id}||'',
      $opts->{no_emails}||$c->{gdpr_unsubscribed_default}||0);
    
   return $db->getLastInsertId;
}

sub randomLogin
{
   my $login = join('', map int rand 10, 1..7);
   while($db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$login)){ $login = join '', map int rand 10, 1..7; }
   return $login;
}

1;
