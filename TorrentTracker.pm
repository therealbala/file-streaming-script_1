package Engine::Components::TorrentTracker;
use strict;
use vars qw($ses $db $c $f);

sub getTorrents
{
   my ($self, %opts) = @_;
   return if !$ses->iPlg('t');

   local *simplifyError = sub {
      my ($str) = @_;
      $str =~ s/.*?&#41;// for(1..2);
      return $str;
   };

   my $filter_user = "AND t.usr_id=" . int($opts{usr_id}) if defined($opts{usr_id});
   my $torrents = $db->SelectARef("SELECT *, u.usr_login, u.usr_premium_expire>NOW() AS premium, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as working
                                FROM Torrents t
                                LEFT JOIN Users u ON u.usr_id=t.usr_id
                                WHERE 1
                                $filter_user");

   for my $t (@$torrents)
   {
      my $files = eval { JSON::decode_json($t->{files}) } if $t->{files};
      $t->{file_list} = join('<br>',map{$ses->SecureStr($_->{path}) . " (<i>".sprintf("%.1f Mb",$_->{size}/1048576)."<\/i>)"} @$files );
      $t->{title} = $ses->SecureStr($t->{name});
      $t->{title}=~s/\/.+$//;
      $t->{title}=~s/:\d+$//;
   
      $t->{percent} = sprintf("%.01f", 100*$t->{downloaded}/$t->{size} ) if $t->{size};
      $t->{working} = $t->{working}>3600*3 ? sprintf("%.1f hours",$t->{working}/3600) : sprintf("%.0f mins",$t->{working}/60);
      $t->{"status_".lc($t->{status})} = 1;
      $t->{error} = simplifyError($t->{error});
   
      $t->{seed_until} = $ses->makeFileSize($t->{size} * $t->{seed_until_rate});
      $t->{download_speed} = $ses->makeFileSize($t->{download_speed});
      $t->{upload_speed} = $ses->makeFileSize($t->{upload_speed});
      $t->{downloaded} = sprintf("%.1f", $t->{downloaded}/1048576 );
      $t->{uploaded} = sprintf("%.1f", $t->{uploaded}/1048576 );
      $t->{size} = sprintf("%.1f", $t->{size}/1048576 );
   }

   return $torrents;
}

1;
