package Engine::Actions::AdminServerAdd;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(save)] );

sub main
{
   my %opts = @_;
   return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
   my $server;
   if ( $f->{srv_id} )
   {
      $server = $db->SelectRow( "SELECT * FROM Servers WHERE srv_id=?", $f->{srv_id} );
      $server->{srv_disk_max} /= 1024 * 1024 * 1024;
      $server->{"s_$server->{srv_status}"} = ' selected';
   }
   elsif ( !$db->SelectOne("SELECT srv_id FROM Servers LIMIT 1") )
   {
      $server->{srv_cgi_url}    = $c->{site_cgi};
      $server->{srv_htdocs_url} = "$c->{site_url}/files";
   }
   $server->{srv_allow_regular} = $server->{srv_allow_premium} = 1 unless $f->{srv_id};
   $server->{srv_cdn} ||= $f->{srv_cdn} || $f->{cdn};

   if ( $server->{srv_cdn} )
   {
      my @cdn_list = grep { $_->{listed} } ( map { $_->options() } $ses->getPlugins('CDN') );
      my ($cdn) = grep { $_->{name} eq $server->{srv_cdn} } @cdn_list;
      $cdn ||= $cdn_list[0];
      $cdn->{selected} = 1 if $cdn;
      return $ses->message("Couldn't find appropriate plugin") if !$cdn;
      my $srv_data = $ses->getSrvData( $server->{srv_id} );
      $_->{value} = $f->{ $_->{name} } || $srv_data->{ $_->{name} } for ( @{ $cdn->{s_fields} } );
      return $ses->PrintTemplate(
         "admin_cdn_form.html",
         %{$server},
         %{$f},
         tests => $opts{tests} || [],
         cdn_list => \@cdn_list,
         s_fields => $cdn->{s_fields},
         srv_name => $cdn->{title},
      );
   }

   return $ses->PrintTemplate(
      "admin_server_form.html",
      %{$server},
      %{$f},
      'tests' => $opts{tests} || [],
      'ftp_mod' => $c->{ftp_mod},
      'mmtt'    => $ses->iPlg('t'),
      'm_g'     => $ses->iPlg('g'),
      'm_3'     => $ses->iPlg('3'),
      'm_v'     => $c->{m_v},
   );
}

sub save
{
   return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};

   $f->{srv_cgi_url}    =~ s/\/$//;
   $f->{srv_htdocs_url} =~ s/\/$//;
   return $ses->message("Server with same cgi-bin URL / htdocs URL already exist in DB")
     if !$f->{srv_id} && $db->SelectOne( "SELECT srv_id FROM Servers WHERE srv_cgi_url=? OR srv_htdocs_url=?",
      $f->{srv_cgi_url}, $f->{srv_htdocs_url} );

   $f->{srv_allow_regular} ||= 0;
   $f->{srv_allow_premium} ||= 0;
   $f->{srv_torrent}       ||= 0;
   $f->{srv_countries}     ||= '';

   my @sflds =
     qw(srv_name srv_ip srv_cgi_url srv_htdocs_url srv_disk_max srv_status srv_key srv_allow_regular srv_allow_premium srv_torrent srv_countries srv_cdn srv_ftp);
   $f->{srv_disk_max} *= 1024 * 1024 * 1024;
   if ( $f->{srv_id} )
   {
      my @dat = map { $f->{$_} || '' } @sflds;
      push @dat, $f->{srv_id};
      $db->Exec( "UPDATE Servers SET " . join( ',', map { "$_=?" } @sflds ) . " WHERE srv_id=?", @dat );
      $c->{srv_status} = $f->{srv_status};
      my $data = join( '~',
         map { "$_:$c->{$_}" }
           qw(site_url site_cgi max_upload_files max_upload_filesize ip_not_allowed srv_status srv_countries) );
      $ses->api2( $f->{srv_id}, { op => 'update_conf', data => $data } );
   }

   my ($cdn) = grep { $_->{name} eq $f->{srv_cdn} } $ses->getPlugins('CDN')->options if $f->{srv_cdn};
   my %srv_data = map { $_->{name} => $f->{ $_->{name} } } @{ $cdn->{s_fields} };
   $ses->setSrvData( $f->{srv_id}, %srv_data ) if $f->{srv_id};

   my $off = $f->{srv_status} eq 'OFF';

   my @tests     = $ses->getPlugins('CDN')->runTests($f) if !$off;
   my $err_count = grep { /ERROR/ } @tests;
   my @arr       = map { { 'text' => $_, 'class' => /ERROR/ ? 'err' : 'ok' } } @tests;

   if ($err_count)
   {
      $f->{srv_disk_max} /= 1024 * 1024 * 1024;
      return main( tests => \@arr );
   }

   unless ( $f->{srv_id} )
   {
      $f->{srv_key} = $c->{fs_key} = $ses->randchar(8);
      $c->{srv_status} = $f->{srv_status};
      $c->{allowed_ip} = $ENV{SERVER_ADDR};

      my $data   = join( '~',
         map { "$_:$c->{$_}" }
           qw(fs_key dl_key site_url site_cgi max_upload_files max_upload_filesize ext_allowed ext_not_allowed ip_not_allowed srv_status allowed_ip)
      );

      if(!$off)
      {
         my $res = $ses->api( $f->{srv_cgi_url}, { op => 'update_conf', data => $data } ) if !$f->{srv_cdn};
         return $ses->message("Unable to update FS config: $res") if $res && $res ne 'OK';
      }

      $db->Exec( "INSERT INTO Servers SET srv_created=CURDATE(), " . join( ',', map { "$_=?" } @sflds ),
         map { $f->{$_} || '' } @sflds );

      my $srv_id = $db->getLastInsertId;
      my %srv_data = map { $_->{name} => $f->{ $_->{name} } } @{ $cdn->{s_fields} };
      $ses->setSrvData( $srv_id, %srv_data ) if $cdn;
   }

   return $ses->redirect('?op=admin_servers');
}

1;
