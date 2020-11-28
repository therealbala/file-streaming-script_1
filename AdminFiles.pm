package Engine::Actions::AdminFiles;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(del_code del_selected transfer_files reencode_selected rethumb_selected untrash_selected)] );

use XUtils;

sub main
{
   my $filter_files;
   $f->{mass_search} =~ s/\r//gs;
   $f->{mass_search} =~ s/\s+\n/\n/gs;

   if ( $f->{mass_search} )
   {
      my @arr;
      for(split(/\n\r?/, $f->{mass_search}))
      {
         push @arr, $1 if /\/(\w{12})(\/|\n|$)/;
         push @arr, decode_nginx_token($1) if $c->{m_n} && /\/d\/([^\/]+)/;
      }
      $filter_files = "AND file_code IN ('" . join( "','", @arr ) . "')";
   }

   $f->{sort_field} ||= 'file_created';
   $f->{sort_order} ||= 'down';
   $f->{per_page}   ||= $c->{items_per_page};
   $f->{usr_id} = $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_login=?", $f->{usr_login} ) if $f->{usr_login};
   my $filter_key       = "AND (file_name LIKE '%$f->{key}%' OR file_code='$f->{key}')" if $f->{key};
   my $filter_user      = "AND f.usr_id='$f->{usr_id}'"                                 if $f->{usr_id} =~ /^\d+$/;
   my $filter_server    = "AND f.srv_id='$f->{srv_id}'"                                 if $f->{srv_id} =~ /^\d+$/;
   my $filter_down_more = "AND f.file_downloads>=$f->{down_more}"                       if $f->{down_more} =~ /^\d+$/;
   my $filter_down_less = "AND f.file_downloads<=$f->{down_less}"                       if $f->{down_less} =~ /^\d+$/;
   my $filter_size_more = "AND f.file_size>=" . $f->{size_more} * 1048576 if $f->{size_more} =~ /^[\d\.]+$/;
   my $filter_size_less = "AND f.file_size<=" . $f->{size_less} * 1048576 if $f->{size_less} =~ /^[\d\.]+$/;
   my $filter_file_real = "AND f.file_real='$f->{file_real}'"             if $f->{file_real} =~ /^\w{12}$/;
   my $filter_trashed   = "AND f.file_trashed > 0" if $f->{trashed_only};

   my $filter_ip = "AND f.file_ip='$f->{ip}'" if $f->{ip} =~ /^[\w:\.]+$/;
   my $files = $db->SelectARef(
      "SELECT f.*, file_downloads*file_size as traffic,
                                       file_ip as file_ip,
                                       u.usr_id, u.usr_login,
                                       UNIX_TIMESTAMP(file_trashed) as trashed_at
                                FROM Files f
                                LEFT JOIN Users u ON f.usr_id = u.usr_id
                                WHERE 1
                                $filter_files
                                $filter_key
                                $filter_user
                                $filter_server
                                $filter_down_more
                                $filter_down_less
                                $filter_size_more
                                $filter_size_less
                                $filter_ip
                                $filter_file_real
                                $filter_trashed
                                "
        . XUtils::makeSortSQLcode( $f, 'file_created' )
        . $ses->makePagingSQLSuffix( $f->{page}, $f->{per_page} )
   );
   my $total = $db->SelectOne(
      "SELECT COUNT(*) as total_count
                                FROM Files f 
                                WHERE 1 
                                $filter_files
                                $filter_key 
                                $filter_user 
                                $filter_server
                                $filter_down_more
                                $filter_down_less
                                $filter_size_more
                                $filter_size_less
                                $filter_ip
                                $filter_file_real
                                $filter_trashed
                                "
   );

   my $current_time = $db->SelectOne("SELECT UNIX_TIMESTAMP()");

   for(@$files)
   {
      $_->{time_left} = timediff( $current_time, $_->{trashed_at} + $c->{trash_expire} * 3600 )
   }

   my $gi;
   if ( $c->{admin_geoip} && -f "$c->{cgi_path}/GeoLite2-Country.mmdb" )
   {
      require Geo::IP2;
      $gi = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
   }

   for (@$files)
   {
      $_->{site_url} = $c->{site_url};
      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} =
        length($file_name) > $c->{display_max_filename}
        ? substr( $file_name, 0, $c->{display_max_filename} ) . '&#133;'
        : $file_name;
      utf8::encode( $_->{file_name_txt} );
      $_->{file_size2}    = $ses->makeFileSize( $_->{file_size} );
      $_->{traffic}       = $_->{traffic} ? $ses->makeFileSize( $_->{traffic} ) : '';
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{file_downloads} ||= '';
      $_->{file_last_download} = '' unless $_->{file_downloads};
      $_->{file_money} = $_->{file_money} eq '0.0000' ? '' : ( $c->{currency_symbol} || '$' ) . $_->{file_money};
      $_->{file_upload_method} = uc($_->{file_upload_method});

      if ($gi)
      {
         $_->{file_country} = $gi->country_code_by_addr( $_->{file_ip} );
      }
   }
   my %sort_hash = XUtils::makeSortHash(
      $f,
      [
         'file_name', 'usr_login', 'file_downloads', 'file_money', 'file_size', 'traffic', 'file_created', 'file_last_download'
      ]
   );

   my $servers = $db->SelectARef("SELECT srv_id,srv_name FROM Servers WHERE srv_status<>'OFF' ORDER BY srv_id");

   $ses->PrintTemplate(
      "admin_files.html",
      'files'              => $files,
      'key'                => $f->{key},
      'usr_id'             => $f->{usr_id},
      'srv_id'             => $f->{srv_id},
      'down_more'          => $f->{down_more},
      'down_less'          => $f->{down_less},
      'size_more'          => $f->{size_more},
      'size_less'          => $f->{size_less},
      "per_$f->{per_page}" => ' checked',
      %sort_hash,
      'paging'         => $ses->makePagingLinks( $f, $total ),
      'items_per_page' => $c->{items_per_page},
      'servers'        => $servers,
      'usr_login'      => $f->{usr_login},
      'token'          => $ses->genToken,
      'm_v'            => $c->{m_v},
      'm_i'            => $c->{m_i},
      'trash_expire'   => $c->{trash_expire}||'',
      'trashed_only'   => $f->{trashed_only}||'',
   );
}

sub del_code
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   my $file = $db->SelectRow(
      "SELECT f.*, u.usr_aff_id
                                    FROM Files f 
                                    LEFT JOIN Users u ON f.usr_id=u.usr_id
                                    WHERE file_code=?", $f->{del_code}
   );
   return $ses->message($ses->{lang}->{lang_no_such_file}) unless $file;
   $file->{del_money} = $c->{del_money_file_del};
   $ses->DeleteFile($file);
   if ( $f->{del_info} )
   {
      $db->Exec( "INSERT INTO DelReasons SET file_code=?, file_name=?, info=?",
         $file->{file_code}, $file->{file_name}, $f->{del_info} );
   }
   return $ses->redirect("$c->{site_url}/?op=admin_files");
}

sub del_selected
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   die "security error" unless $ses->getEnv('REQUEST_METHOD') eq 'POST';
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)");
   $_->{del_money} = $c->{del_money_file_del} for @$files;
   $ses->DeleteFilesMass($files);
   if ( $f->{del_info} )
   {

      for (@$files)
      {
         $db->Exec( "INSERT INTO DelReasons SET file_code=?, file_name=?, info=?",
            $_->{file_code}, $_->{file_name}, $f->{del_info} );
      }
   }

   return $ses->redirect("$c->{site_url}/?op=admin_files");
}

sub transfer_files
{
   require Engine::Actions::AdminServers;
   return Engine::Actions::AdminServers->transfer_files();
}

sub reencode_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $files	= $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)");

   for my $file(@$files)
   {
      next if $file->{file_name} !~ /\.(avi|divx|xvid|mpg|mpeg|vob|mov|3gp|flv|mp4|wmv|mkv)$/i;

      $db->Exec("INSERT IGNORE INTO QueueEncoding
           SET file_real=?,
               file_id=?,
               srv_id=?,
               created=NOW()",
           $file->{file_real},
           $file->{file_id},
           $file->{srv_id});
   }

   return $ses->redirect("$c->{site_url}/?op=admin_files");
}

sub rethumb_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;

   my $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)");
   my @subset = grep { $_->{file_name} =~ /\.(jpg|jpeg|gif|png|bmp)$/i } @$files;
   $_->{dx} = sprintf( "%05d", ( $_->{file_real_id} || $_->{file_id} ) / $c->{files_per_folder} ) for @subset;
   my %group;

   $group{ $_->{srv_id} } = $_ for @subset;

   for my $srv_id ( keys %group )
   {
      my $res = $ses->api2(
         $srv_id,
         {
            op         => 'rethumb',
            list       => join( "\n", map { "$_->{dx}:$_->{file_real}" } @subset ),
            file_names => join( "\n", map { $_->{file_name} } @subset ),
         }
      );
      $ses->message("$ses->{lang}->{lang_error_occured}:$res") if $res !~ /^OK/;
   }

   return $ses->redirect("$c->{site_url}/?op=admin_files");
}

sub untrash_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=? AND file_id IN ($ids)", $ses->getUserId );
   &UntrashFiles(@$files);
   return $ses->redirect("$c->{site_url}/?op=admin_files");
}

sub decode_nginx_token
{
   require HCE_MD5;
   my ($code) = @_;
   my $hce = HCE_MD5->new($c->{dl_key}, "XFileSharingPRO");
   my ($srv_id, $file_id) = unpack("SL", $hce->hce_block_decrypt($ses->decode32($code)) );
   return $db->SelectOne("SELECT file_code FROM Files WHERE file_id=?", $file_id);
}

# TODO: code was copy-pasted from MyFiles.pm, refactoring is needed

sub timediff
{
   my $interval = $_[1] - $_[0];
   return int( $interval / 3600 ) . " hours" if $interval > 3600;
   return int( $interval / 60 ) . " minutes" if $interval > 60;
   return $interval . " seconds";
}

sub UntrashFiles
{
   my (@files) = @_;
   for my $file (@files)
   {
      $db->Exec("UPDATE Files SET file_trashed=0 WHERE file_id=?", $file->{file_id});

      # Traversing folders tree until root
      my $folder = $db->SelectRow("SELECT * FROM Folders WHERE fld_id=?", $file->{file_fld_id});
	   while($folder)
      {
         $db->Exec("UPDATE Folders SET fld_trashed=0 WHERE fld_id=?", $folder->{fld_id});
         $folder = $db->SelectRow("SELECT * FROM Folders WHERE fld_id=?", $folder->{fld_parent_id});
      }
   }
}

1;
