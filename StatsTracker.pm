package Engine::Components::StatsTracker;
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

sub registerEvent
{
   my ($self, $event, $opts) = @_;

   if($event eq 'profits_received')
   {
      my @required = qw(usr_id amount stats);
      my @defined = qw(); 
      _check(%$opts, @required, @defined);

      $db->Exec("INSERT INTO Stats2
            SET usr_id=?, day=CURDATE(), profit_$opts->{stats}=profit_$opts->{stats}+?
            ON DUPLICATE KEY UPDATE profit_$opts->{stats}=profit_$opts->{stats}+?",
            $opts->{usr_id}, $opts->{amount}, $opts->{amount});

      $db->Exec("UPDATE Stats2 SET $opts->{stats}=$opts->{stats}+1 WHERE usr_id=? AND day=CURDATE()", $opts->{usr_id})
         if($opts->{stats} =~ /^(downloads|sales|rebills)$/);

      $db->Exec("INSERT INTO Stats
         SET paid_to_users=?, day=CURDATE()
         ON DUPLICATE KEY UPDATE
         paid_to_users=paid_to_users+?",
         $opts->{amount},
         $opts->{amount});
   }
   elsif($event eq 'payment_accepted')
   {
      return if $opts->{ignore_admin_stats};

      $db->Exec("INSERT INTO Stats
         SET received=?, day=CURDATE()
         ON DUPLICATE KEY UPDATE
         received=received+?",
         $opts->{amount},
         $opts->{amount});
   }
   else
   {
      die("Unknown event type: $event");
   }
}

1;
