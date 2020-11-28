package Engine::Components::PaymentAcceptor;
use strict;
use vars qw($ses $db $c $f);

sub _check(\%\@\@)
{
   my ($opts, $required, $defined) = @_;
   my %valid = map { $_ => 1 } (@$required, @$defined);

   my ($pkg, $fn, $ln) = caller(1);
   for(@$required) { die("Required option: $_ at $fn:$ln\n") if !defined($opts->{$_}); }
   for(keys %$opts) { die("Unknown option: $_ at $fn:$ln\n") if !$valid{$_}; }
}

sub createTransaction
{
   my ($self, %opts) = @_;

   my @required = qw(usr_id amount);
   my @defined = qw(days ip aff_id file_id ref_url email target plugin type referer);
   _check(%opts, @required, @defined);

   my $id = int(1+rand 9).join('', map {int(rand 10)} 1..9);
   $id = int scalar(rand(2**30)) if $opts{type} =~ /^(webmoney|robokassa)$/;
   $db->Exec("INSERT INTO Transactions SET id=?,
                      usr_id=?,
                      amount=?,
                      days=?,
                      ip=?,
                      created=NOW(),
                      aff_id=?,
                      file_id=?,
                      ref_url=?,
                      email=?,
                      verified=?,
                      target=?,
                      plugin=?",
                   $id,
                   $opts{usr_id},
                   $opts{amount},
                   $opts{days}||0,
                   $ses->getIP()||'0.0.0.0',
                   $opts{aff_id}||0,
                   $opts{file_id}||0,
                   $opts{referer}||'',
                   $opts{email}||'',
                   $opts{verified}||0,
                   $opts{target}||'',
                   $opts{type}||'',
                   );
   return $db->SelectRow("SELECT * FROM Transactions WHERE id=?", $id);
}

sub processTransaction
{
   my ($self, $transaction, %opts) = @_;

   (sub {
      return $self->addPremiumTraffic($transaction) if $transaction->{target} eq 'premium_traffic';
      return $self->addResellersMoney($transaction) if $transaction->{target} eq 'reseller';
      return $self->addVIPFileAccess($transaction) if $transaction->{target} =~ /^file_(\d+)_access$/;
      return $self->addPremiumDays($transaction);
   })->();

   $db->Exec("UPDATE Transactions SET verified=1, txn_id=? WHERE id=?", $f->{txn_id}, $transaction->{id});

   my $profitsCharger = $ses->require("Engine::Components::ProfitsCharger");
   $profitsCharger->chargeAffs($transaction) if $transaction->{target} ne 'reseller';

   my $statsTracker = $ses->require("Engine::Components::StatsTracker");
   $statsTracker->registerEvent('payment_accepted', { amount => $transaction->{amount}, %opts });
}

sub getAvailablePaymentMethods
{
   my %settings = map { $_->{name} => $_ } @{ $db->SelectARef("SELECT * FROM PaymentSettings") };

   local *priority = sub {
      my $pos = $settings{$_[0]->{name}}->{position};
      return "1-$pos" if $pos;
      return "2-$_[0]->{name}";
   };

   my @payment_types;
   for my $opts($ses->getPlugins('Payments')->get_payment_buy_with())
   {
      if($opts->{submethods})
      {
         push @payment_types, { %$opts, %$_, submethod => $_->{name}, name => $opts->{name} } for @{ $opts->{submethods} };
      }
      else
      {
         push @payment_types, { %$opts };
      }
   }

   @payment_types = sort { priority($a) cmp priority($b) } @payment_types;
   return @payment_types;
}

sub addResellersMoney
{
   my ($self, $transaction) = @_;
   print STDERR "Adding $transaction->{amount} of money to reseller $transaction->{usr_id}\n";
   $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?",
         $transaction->{amount},
         $transaction->{usr_id});
}

sub addVIPFileAccess
{
   my ($self, $transaction) = @_;
   print STDERR "Granting user $transaction->{usr_id} with an access to file $transaction->{file_id}\n";
   $db->Exec("INSERT IGNORE INTO PremiumPackages SET usr_id=?, type=?, quantity=1",
      $transaction->{usr_id},
      $transaction->{target});
}

sub addPremiumTraffic
{
   my ($self, $transaction) = @_;
   my $traffic = $ses->ParsePlans($c->{traffic_plans}, 'hash')->{$transaction->{amount}};;
   print STDERR "Adding $traffic GBs of traffic to usr_id=$transaction->{usr_id}\n";
   $db->Exec("UPDATE Users SET usr_premium_traffic=usr_premium_traffic + ? WHERE usr_id=?",
      $traffic * 2**30,
      $transaction->{usr_id});
}

sub addPremiumDays
{
   my ($self, $transaction, %opts) = @_;

   my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $transaction->{usr_id} );
   my $days = $opts{days}||$transaction->{days}||$ses->ParsePlans($c->{payment_plans}, 'hash')->{$transaction->{amount}};
   die("No such plan: $transaction->{amount} $c->{currency_code}") if !$days;
   my $add_seconds = $days*24*3600;

   $db->Exec("UPDATE Users SET usr_premium_expire=GREATEST(usr_premium_expire,NOW()) + INTERVAL ? SECOND WHERE usr_id=?",
         $add_seconds, $transaction->{usr_id});

   my $new_expire_time = $db->SelectOne("SELECT usr_premium_expire FROM Users WHERE usr_id=?", $transaction->{usr_id});
   print STDERR  "New expire time is : $new_expire_time" ;

   my $expire = $db->SelectOne("SELECT usr_premium_expire FROM Users WHERE usr_id=?", $user->{usr_id});
	my $t = $ses->CreateTemplate("payment_notification.html");
	$t->param('amount' => $transaction->{amount},
	                'days'   => $days,
	                'expire' => $expire,
	                'login'  => $transaction->{login},
	                'password' => $transaction->{password},
	         );
	$c->{email_text}=1;

	$ses->SendMail($user->{usr_email}, $c->{email_from}, "$c->{site_name} Payment Notification", $t->output) if $user->{usr_email};

	# Send email to admin
	my $t = $ses->CreateTemplate("payment_notification_admin.html");
	$t->param('amount' => $transaction->{amount},
	                'days'   => $days,
	                'expire' => $expire,
	                'usr_id' => $user->{usr_id},
	                'usr_login' => $user->{usr_login},
	         );
	$c->{email_text}=0;
	$ses->SendMail($c->{contact_email}, $c->{email_from}, "Received payment from $user->{usr_login}", $t->output);
}

1;
