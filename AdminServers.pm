package Engine::Actions::AdminServers;
use strict;
use XUtils;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(transfer_files update_srv_stats delete)] );

use JSON;

sub main
{
   my $servers = $db->SelectARef(
      "SELECT s.*
                                  FROM Servers s
                                  ORDER BY srv_created
                                 "
   );
   for (@$servers)
   {
      $_->{srv_disk_percent} = sprintf( "%.01f", 100 * $_->{srv_disk} / $_->{srv_disk_max} ) if $_->{srv_disk_max};
      $_->{srv_disk} = sprintf( "%.01f", $_->{srv_disk} / 1073741824 );
      $_->{srv_disk_max} = int $_->{srv_disk_max} / 1073741824;
      my @a;
      push @a, "Regular" if $_->{srv_allow_regular};
      push @a, "Premium" if $_->{srv_allow_premium};
      $_->{user_types} = join '<br>', @a;
      $_->{ lc( $_->{srv_status} ) } = 1;
      $_->{not_off} = 1 if $_->{srv_status} ne 'OFF';
   }

   my @servers = map { { srv_id => $_->{srv_id}, srv_name => $_->{srv_name} } } @$servers;

   $ses->PrintTemplate( "admin_servers.html",
      'servers' => $servers,
      'servers_json' => JSON::encode_json(\@servers),
      'm_e'            => $c->{m_e});
}

sub transfer_files
{
   my $from = _select_servers($f->{srv_id1}) if $f->{srv_id1};
   my $to = _select_servers($f->{srv_id2});

   return $ses->message("Need to specify destination server(s)") if !@$to;
   return $ses->message("Can't fill more than 100% of disk space") if $f->{limit_type} eq 'fill_up_to' && $f->{limit_value} > 100;

   my $srv_ids = join(',', map { $_->{srv_id} } @$from) if $from;
   my $file_ids = join(',', @{XUtils::ARef($f->{file_id})}) if $f->{file_id};

   my $files = [];
   $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($file_ids)") if $file_ids;
   $files = $f->{order} =~ /^popular_/ ? _select_top48($from, $f->{order}) : _select_files($from, $f->{order}) if $f->{order};

   my $occupation = $f->{limit_type} eq 'fill_up_to' ? $f->{limit_value} : 100;
   my $max_size = _translate_size_units($f->{limit_value}, $f->{size_units}) if $f->{limit_type} eq 'total_size';

   my $bytes_enqueued = 0;
   my $i = 0;
   my %files_seen;

   for($i = 0; $i < @$files; $i++)
   {
      my $file = $files->[$i];
      my @candidates = grep { ($_->{srv_disk_max} - _queue_size($_->{srv_id})) >= $file->{file_size} } @$to;
      last if !@candidates;
      next if !$file->{file_real};

      $bytes_enqueued += $file->{file_size};
      last if $f->{limit_type} eq 'total_size' && $bytes_enqueued > $max_size;
      last if $f->{limit_type} eq 'files_count' && $i >= $f->{limit_value};

      my $dest = $candidates[$i % int(@candidates)];
      $files_seen{$file->{file_real}} = 1;

      $db->Exec("DELETE FROM QueueTransfer WHERE file_real=?", $file->{file_real});
      $db->Exec("INSERT IGNORE INTO QueueTransfer
                 SET file_real=?,
                     file_id=?,
                     srv_id1=?,
                     srv_id2=?,
                     created=NOW()",
                 $file->{file_real},
                 $file->{file_id},
                 $file->{srv_id},
                 $dest->{srv_id});
   }

   my $number_enqueued = int(keys(%files_seen)); # Using $i may entail invalid results here due to Anti-Dupe mod
   return $ses->redirect_msg("$c->{site_url}/?op=admin_servers", "$number_enqueued files enqueued");
}

sub update_srv_stats
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   return $ses->message($ses->{lang}->{lang_no_servers_selected})      if !$f->{srv_id};
   my $ids = join ',', @{ XUtils::ARef( $f->{srv_id} ) };
   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_id IN ($ids)");
   for my $s (@$servers)
   {
      my $res = $ses->api2($s->{srv_id}, { op => 'get_disk_space' });
      my $ret = JSON::decode_json($res);
      return $ses->message("$ses->{lang}->{lang_error_when_requesting_api} .<br>$res") if !$ret->{total};

      my $file_count = $db->SelectOne( "SELECT COUNT(*) FROM Files WHERE srv_id=?", $s->{srv_id} );

      $db->Exec("UPDATE Servers SET srv_files=?, srv_disk=?, srv_disk_max=?, srv_last_updated=NOW() WHERE srv_id=?",
         $file_count,
         $ret->{total} - $ret->{available},
         $ret->{total},
         $s->{srv_id});
   }
   return $ses->redirect('?op=admin_servers');
}

sub delete
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   my %opts = (disable_captcha_check => 1, disable_2fa_check => 1, disable_login_ips_check => 0);
   my $user = $ses->require("Engine::Components::Auth")->checkLoginPass( $ses->getUser->{usr_login}, $f->{password}, %opts);
   return $ses->message($ses->{lang}->{lang_wrong_password}) if !$user;

   my $srv = $db->SelectRow( "SELECT * FROM Servers WHERE srv_id=?", $f->{srv_id} );
   return $ses->message($ses->{lang}->{lang_no_such_server}) unless $srv;

   $db->Exec( "DELETE FROM Files WHERE srv_id=?",   $srv->{srv_id} );
   $db->Exec( "DELETE FROM Servers WHERE srv_id=?", $srv->{srv_id} );

   return $ses->redirect('?op=admin_servers');
}

sub _filters
{
   my @filters;
   push @filters, "AND file_downloads >= " . int($f->{filter_downloads_more}) if $f->{filter_downloads_more};
   push @filters, "AND file_downloads < " . int($f->{filter_downloads_less}) if $f->{filter_downloads_less};
   return join(" ", @filters);
}

sub _select_servers
{
   my ($srv_ids) = @_;
   $srv_ids =~ s/[^0-9,]//g;
   return $db->SelectARef("SELECT * FROM Servers WHERE srv_id IN ($srv_ids)") if $srv_ids;
}

sub _select_files
{
   my $servers = shift;
   my $order = _translate_order(shift);

   my $srv_ids = join(',', map { $_->{srv_id} } @$servers);
   my $filters = _filters();
   return $db->SelectARef("SELECT * FROM Files WHERE srv_id IN ($srv_ids) $filters ORDER BY $order");
}

sub _select_top48
{
   my $servers = shift;
   my $order = _translate_order(shift);

   my $srv_ids = join(',', map { $_->{srv_id} } @$servers);
   my $filters = _filters();
   return $db->SelectARef("SELECT f.*, COUNT(*) as downloads, SUM(size) AS traffic
      FROM IP2Files i
      LEFT JOIN Files f ON f.file_id=i.file_id
      WHERE DATE(created) >= NOW() - INTERVAL 2 DAY
      AND srv_id IN ($srv_ids)
      $filters
      GROUP BY f.file_real
      ORDER BY $order");
}

sub _translate_order
{
   my ($order) = @_;

   return "traffic ASC" if $order eq 'popular_enc';
   return "traffic DESC" if $order eq 'popular_desc';
   return "file_size ASC" if $order eq 'size_enc';
   return "file_size DESC" if $order eq 'size_desc';
   return "file_id ASC" if $order eq 'id_enc';
   return "file_id DESC" if $order eq 'id_desc';

   die("Unknown order: $order");
}

sub _translate_size_units
{
   my ($size, $value) = @_;

   return $size * 2**10 if lc($value) eq 'kb';
   return $size * 2**20 if lc($value) eq 'mb';
   return $size * 2**30 if lc($value) eq 'gb';
   return $size * 2**40 if lc($value) eq 'tb';

   die("Unknown unit: $value");
}

sub _queue_size
{
   my ($srv_id) = @_;
   return $db->SelectOne("SELECT SUM(file_size) FROM QueueTransfer q
      LEFT JOIN Files f ON f.file_id = q.file_id
      WHERE q.srv_id2=$srv_id");
}

1;
