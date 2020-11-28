package Engine::Actions::MyFiles;
use strict;
use Digest::MD5 qw(md5_hex);

use XFileConfig;
use Engine::Core::Action (
   'IMPLEMENTS' => [
      qw(del_code del_selected del_folder untrash_selected set_flag create_new_folder add_my_acc del_torrent torrents load_files_list load_folders_list to_folder_move to_folder_copy zip)
   ]
);

use XUtils;
use List::Util qw(min sum);

use MIME::Base64;
use JSON;
use HCE_MD5;

sub main
{
   $f->{sort_field} ||= 'file_created';
   $f->{sort_order} ||= 'down';
   $f->{fld_id}     ||= 0;
   my ( $files, $total );
   my $folders = [];
   return $ses->message($ses->{lang}->{lang_invalid_folder_id}) if $f->{fld_id} > 0 && _curr_folder()->{usr_id} != $ses->getUserId;

   $f->{key} = $f->{term} if $f->{term};    # autocomplete

   my $files = _select_files();
   my $files_total = _select_files_total();
   my $folders = _select_folders();
   my $folders_total = _select_folders_total();

   my $totals =
     $db->SelectRow( "SELECT COUNT(*) as total_files, SUM(file_size) as total_size FROM Files WHERE usr_id=?",
      $ses->getUserId );

   my $trashed = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=? AND file_trashed > 0", $ses->getUserId );
   unshift @$folders, { fld_id => -1, fld_name_txt => 'Trash', files_total => int(@$trashed), trash => 1 }
     if !$f->{fld_id} && @$trashed > 0;
   unshift @$folders, { fld_id => _curr_folder()->{fld_parent_id}, fld_name_txt => '&nbsp;. .&nbsp;' } if $f->{fld_id};

   my @folders_tree = XUtils::buildFoldersTree( usr_id => $ses->getUserId );

   my $torrents = $ses->require("Engine::Components::TorrentTracker")->getTorrents(usr_id => $ses->getUserId);

   my $smartp = 1 if $ses->iPlg('p') && $c->{m_p_premium_only};

   my $total_size = $db->SelectOne( "SELECT SUM(file_size) FROM Files WHERE usr_id=?", $ses->getUserId );
   my $disk_space = ( $ses->{user}->{usr_disk_space} || $c->{disk_space} ) * 2**20;
   my $occupied_percent = min( 100, int( $total_size * 100 / $disk_space ) ) if $disk_space;

   my $current_folder = $db->SelectRow( "SELECT * FROM Folders WHERE fld_id=?", $f->{fld_id} );

   $totals->{total_size} = $ses->makeFileSize( $totals->{total_size} );
   $disk_space = $disk_space ? $ses->makeFileSize($disk_space) : 'Unlimited';

   $ses->PrintTemplate(
      "my_files.html",
      'files'          => $files,
      'folders'        => $folders,
      'folders_tree'   => \@folders_tree,
      'folder_id'      => $f->{fld_id},
      'folder_name'    => shorten( _curr_folder()->{fld_name} ),
      'fld_descr'      => _curr_folder()->{fld_descr},
      'key'            => $f->{key},
      'disk_space'     => $disk_space,
      'deleted_num'    => $db->SelectOne( "SELECT COUNT(*) FROM FilesDeleted WHERE usr_id=? AND hide=0", $ses->getUserId ),
      'per_page'       => $f->{per_page} || $c->{items_per_page} || 5,
      'current_folder' => shorten( _curr_folder()->{fld_name} || '', 30 ),
      'torrents'       => $torrents||[],
      'smartp'         => $smartp,
      'enable_file_comments' => $c->{enable_file_comments},
      'token'                => $ses->genToken,
      'occupied_percent'     => $occupied_percent || 0,
      'current_fld_id'       => _curr_folder() ? _curr_folder()->{fld_id} : '',
      'trash'                => $f->{fld_id} < 0 ? 1 : 0,
      'folders_total'        => $folders_total,
      'files_total'          => $files_total,
      'page'                 => $f->{page}||1,
      'allow_vip_files'      => $ses->getUser->{usr_allow_vip_files}||$c->{allow_vip_files},
      'm_b'                  => $c->{m_b}||0,
      %{$totals},
      _sort_hash(),
   );
}

sub del_code
{
   my $file = $db->SelectRow( "SELECT * FROM Files WHERE file_code=? AND usr_id=?", $f->{del_code}, $ses->getUserId );
   return $ses->message($ses->{lang}->{lang_no_such_file}) unless $file;
   $ses->{no_del_log} = 1;
   &TrashFiles($file);
   return $ses->redirect("?op=my_files");
}

sub del_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=? AND file_id IN ($ids)", $ses->getUserId );
   $| = 1;
   print "Content-type:text/html\n\n<html><body>\n\n";
   $ses->{no_del_log} = 1;
   &TrashFiles(@$files);
   print "<script>window.location='$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}';</script>";
   return;
   return    #$ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
}

sub del_folder
{
   my $fld = $db->SelectRow( "SELECT * FROM Folders WHERE usr_id=? AND fld_id=?", $ses->getUserId, $f->{del_folder} );
   return $ses->message($ses->{lang}->{lang_no_such_folder}) unless $fld;
   $ses->{no_del_log} = 1;
   &delFolder( $f->{del_folder} );
   return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
}

sub untrash_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=? AND file_id IN ($ids)", $ses->getUserId );
   &UntrashFiles(@$files);
   return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=-1");
}

sub set_flag
{
   my @file_ids = @{ XUtils::ARef( $f->{'file_id[]'} ) };
   my $name = $1 if $f->{set_flag} =~ /^(file_public|file_premium_only)$/;
   $db->Exec(
      "UPDATE Files SET $name=? WHERE usr_id=? AND file_id IN (" . join( ',', @file_ids ) . ")",
      $f->{value} eq 'true' ? 1 : $f->{value},
      $ses->getUserId,
   );
   print "Content-type: text\plain\n\nOK";
   return;
}

sub create_new_folder
{
   $f->{create_new_folder} = $ses->SecureStr( $f->{create_new_folder} );
   return $ses->message($ses->{lang}->{lang_invalid_folder_name}) unless $f->{create_new_folder};
   return $ses->message($ses->{lang}->{lang_invalid_parent_folder})
     if $f->{fld_id}
     && !$db->SelectOne( "SELECT fld_id FROM Folders WHERE usr_id=? AND fld_id=?", $ses->getUserId, $f->{fld_id} );
   $db->Exec( "INSERT INTO Folders SET usr_id=?, fld_parent_id=?, fld_name=?",
      $ses->getUserId, $f->{fld_id}, $f->{create_new_folder} );
   return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
}

sub del_torrent
{
   my $torr = $db->SelectRow( "SELECT * FROM Torrents WHERE sid=? AND usr_id=?", $f->{del_torrent}, $ses->getUserId );
   return $ses->redirect("$c->{site_url}/?op=my_files") unless $torr;
   my $res = $ses->api2(
      $torr->{srv_id},
      {
         op  => 'torrent_delete',
         sid => $f->{del_torrent},
      }
   );

   $db->Exec( "DELETE FROM Torrents WHERE sid=?", $f->{del_torrent} );
   return $ses->redirect("$c->{site_url}/?op=my_files");
}

sub load_folders_list
{
   $f->{sort_field} ||= 'file_created';
   $f->{sort_order} ||= 'down';

   my $folders = _select_folders();

   $ses->{form}->{no_hdr} = 1;
   $ses->PrintTemplate(
      'folders.html',
      'current_folder' => shorten( _curr_folder()->{fld_name} || '' ),
      'current_fld_id' => _curr_folder() ? _curr_folder()->{fld_id} : '',
      'fld_descr'      => _curr_folder()->{fld_descr},
      'folders'        => $folders,
      'token'          => $ses->genToken,
   );
   return;
}

sub load_files_list
{
   $f->{sort_field} ||= 'file_created';
   $f->{sort_order} ||= 'down';

   my $files = _select_files();
   my @folders_tree = XUtils::buildFoldersTree( usr_id => $ses->getUserId );

   delete $f->{load_files_list}; # Prevent sort breaking after AJAX request performed
   my %sort_hash = _sort_hash(),

   $ses->{form}->{no_hdr} = 1;

   $ses->PrintTemplate(
      'files.html',
      files            => $files,
      'token'          => $ses->genToken,
      'folders_tree'   => \@folders_tree,
      'current_fld_id' => _curr_folder() ? _curr_folder()->{fld_id} : '',
      'allow_vip_files' => $ses->getUser->{usr_allow_vip_files}||$c->{allow_vip_files},
      trash            => $f->{fld_id} < 0 ? 1 : 0,
      %sort_hash,
   );
   return;
}

sub to_folder_move
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $fld_id =
     $db->SelectOne( "SELECT fld_id FROM Folders WHERE usr_id=? AND fld_id=?", $ses->getUserId, $f->{to_folder} ) || 0;
   $db->Exec( "UPDATE Files SET file_fld_id=? WHERE usr_id=? AND file_id IN ($ids)", $fld_id, $ses->getUserId );
   return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
}

sub to_folder_copy
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $fld_id =
     $db->SelectOne( "SELECT fld_id FROM Folders WHERE usr_id=? AND fld_id=?", $ses->getUserId, $f->{to_folder} ) || 0;

   #$db->Exec("UPDATE Files SET file_fld_id=? WHERE usr_id=? AND file_id IN ($ids)",$fld_id,$ses->getUserId);
   my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=? AND file_id IN ($ids)", $ses->getUserId );
   for my $ff (@$files)
   {
      &CloneFile( $ff, fld_id => $f->{to_folder} );
   }
   return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
}

sub zip
{
   my $server = XUtils::SelectServer( $ses, $ses->getUser() );
   return $ses->message("No upload server") if !$server;

   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } );
   return $ses->redirect("$c->{site_url}/?op=my_files") if !$ids;

   my $files = $db->SelectARef( "SELECT f.*, s.srv_cgi_url
      FROM Files f
      LEFT JOIN Servers s ON s.srv_id = f.srv_id
      WHERE usr_id=?
      AND file_id IN ($ids)",
      $ses->getUserId );
   return $ses->message("No files to zip") if !@$files;

   my $req = {};
   $req->{output_filename} = 'bulk_download.zip';
   $req->{ip} = $ses->getIP;
   $req->{expires} = time() + $c->{symlink_expire}*3600;
   $req->{files} = [];

   for my $file(@$files)
   {
      push @{ $req->{files} }, {
         post_url => "$file->{srv_cgi_url}/zip.cgi",
         dx => sprintf("%05d", ($file->{file_real_id}||$file->{file_id})/$c->{files_per_folder}),
         file_real => $file->{file_real},
         file_name => $file->{file_name},
      };
   }

   my $hce = HCE_MD5->new($c->{dl_key}, "XFileSharingPRO");
   my $payload = encode_base64($hce->hce_block_encrypt(JSON::encode_json($req)), '');
   print "Content-type: text/html\n\n";
   print <<BLOCK
<HTML><BODY onLoad="document.F1.submit();">
<form name="F1" action="$server->{srv_cgi_url}/zip.cgi" method="POST">
   <input type="hidden" name="payload" value="$payload">
</form>
</BODY></HTML>
BLOCK
;
}

sub timediff
{
   my $interval = $_[1] - $_[0];
   return int( $interval / 3600 ) . " hours" if $interval > 3600;
   return int( $interval / 60 ) . " minutes" if $interval > 60;
   return $interval . " seconds";
}

sub shorten
{
   my ( $str, $max_length ) = @_;
   $max_length ||= $c->{display_max_filename};
   return length($str) > $max_length ? substr( $str, 0, $max_length ) . '&#133;' : $str;
}

sub TrashFiles
{
   return if !@_;
   return $ses->DeleteFilesMass(\@_) if !$c->{trash_expire};
   my $file_ids = join(",", map { $_->{file_id} } @_);
   $db->Exec("UPDATE Files SET file_trashed=NOW() WHERE file_id IN ($file_ids)");

   if($c->{memcached_location})
   {
      $db->Uncache( 'file', $db->SelectOne("SELECT file_code FROM Files WHERE file_id=?", $_->{file_id} ) ) for @_;
   }
}

sub TrashFolder
{
   my ($fld_id) = @_;
   return $db->Exec("DELETE FROM Folders WHERE fld_id=?", $fld_id) if !$c->{trash_expire};
   $db->Exec("UPDATE Folders SET fld_trashed=1 WHERE fld_id=?", $fld_id);
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

sub delFolder
{
   my ($fld_id)=@_;
   my $subf = $db->SelectARef("SELECT * FROM Folders WHERE usr_id=? AND fld_parent_id=?",$ses->getUserId,$fld_id);
   for(@$subf)
   {
      &delFolder($_->{fld_id});
   }
   my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=? AND file_fld_id=?",$ses->getUserId,$fld_id);
   &TrashFiles(@$files);
   &TrashFolder($fld_id);
}

sub CloneFile
{
   my ($file,%opts) = @_;
   my $db = $ses->db;

   my $code = $ses->randchar(12);
   while($db->SelectOne("SELECT file_id FROM Files WHERE file_code=? OR file_real=?",$code,$code)){$code = $ses->randchar(12);}

   $db->Exec("INSERT INTO Files 
        SET usr_id=?, 
            srv_id=?,
            file_fld_id=?,
            file_name=?, 
            file_descr=?, 
            file_public=?, 
            file_code=?, 
            file_real=?, 
            file_real_id=?, 
            file_del_id=?, 
            file_size=?,
            file_size_encoded=?,
            file_password=?, 
            file_ip=?, 
            file_md5=?, 
            file_spec=?, 
            file_upload_method='copy',
            file_created=NOW(), 
            file_last_download=NOW()",
         $opts{usr_id}||$ses->getUserId,
         $file->{srv_id},
         $opts{fld_id}||0,
         $file->{file_name},
         '',
         1,
         $code,
         $file->{file_real},
         $file->{file_real_id}||$file->{file_id},
         $file->{file_del_id},
         $file->{file_size},
         $file->{file_size_encoded},
         $opts{file_password}||'',
         $opts{ip}||$ses->getIP,
         $file->{file_md5},
         $file->{file_spec}||'',
       );
   $db->Exec("UPDATE Servers SET srv_files=srv_files+1 WHERE srv_id=?",$file->{srv_id});
   return $code;
}

sub add_my_acc
{
   require URI;
   my @file_codes = map { URI->new($_)->path =~ /\/(\w{12})/ } split("\n", $f->{url_mass});
   $file_codes[0] ||= $f->{add_my_acc};
   my $ids = join("','",grep{/^\w+$/} @file_codes);
   my $files = $db->SelectARef("SELECT * FROM Files
                     WHERE file_code IN ('$ids')");
   my $fld_id = $db->SelectOne("SELECT fld_id FROM Folders WHERE fld_id=? AND usr_id=?",
                     $f->{to_folder},
                     $ses->getUserId);
   for(@$files) {
       $_->{file_status} = "non-public file" if !$_->{file_public};
      next if $_->{file_status};
      $_->{file_password} ||= $f->{link_pass};
      my $total_size = $db->SelectOne("SELECT SUM(file_size) FROM Files WHERE usr_id=?",
                     $ses->getUserId);
      my $disk_space = $ses->{user}->{usr_disk_space} || $c->{disk_space};
      if(!$disk_space || $disk_space && $total_size + $_->{file_size} < $disk_space * 2**20)
      {
         $_->{file_code_new} = CloneFile($_,
                        fld_id => $fld_id||0,
                        file_password => $_->{file_password}||'');
         $_->{file_status} ||= 'OK';
      }
      else
      {
         $_->{file_status} ||= 'Disk quota exceeded';
      }
   }
   
   # Case 1: the files were added through upload form
   if($f->{url_mass}) {
      my @har;
      push @har, { name => 'op', value => 'upload_result' };
      push @har, { name => 'link_rcpt', value => $f->{link_rcpt} } if $f->{link_rcpt};
      for(@$files) {
         push @har, { name => 'fn', value => $_->{file_code_new} || $_->{file_name} };
         push @har, { name => 'st', value => $_->{file_status}||'OK' };
      }
      print "Content-type: text/html\n\n";
      print"<HTML><BODY><Form name='F1' action='' method='POST'>";
      print"<input type='hidden' name='$_->{name}' value='$_->{value}'>" for @har;
      print"</Form><Script>document.location='javascript:false';document.F1.submit();</Script></BODY></HTML>";
      return;
   }

   # Case 2: the files were added through AJAX
   my @has_errors = grep { $_->{file_status} ne 'OK' } @$files;
   print"Content-type:text/html\n\n";
   print @has_errors ? $has_errors[0]->{file_status} : $ses->{lang}->{lang_added_to_account};
   return;
}

sub torrents
{
   my $t = $ses->CreateTemplate('my_files_torrents.html');
   my $torrents = $ses->require("Engine::Components::TorrentTracker")->getTorrents(usr_id => $ses->getUserId);
   $t->param( torrents => $torrents );
   return print "Content-type: text/html\n\n", $t->output;
}

sub _curr_folder
{
   return {} if !$f->{fld_id};
   return $db->SelectRow( "SELECT * FROM Folders WHERE fld_id=?", $f->{fld_id} ) || {};
}

sub _sort_hash
{
   return XUtils::makeSortHash( $f,
      [ 'file_name', 'file_downloads', 'comments', 'file_size', 'file_public', 'file_created', 'file_premium_only', 'file_price' ] );
}

sub _build_filters
{
   my $filter_key = "AND (file_name LIKE '%$1%' OR file_descr LIKE '%$1%')" if $f->{key} =~ /([^'\\]+)/;
   my $filter_trash = "AND f.file_trashed" . ( $f->{fld_id} == -1 ? " > 0" : " = 0" );
   my $filter_fld = "AND f.file_fld_id='$1'" if !$filter_key && $f->{fld_id} >= 0 && $f->{fld_id} =~ /^(\d+)$/;
   my $filter_trashed_folder = "AND fld_trashed" . ( $f->{fld_id} == -1 ? " > 0" : " = 0" );

   my $filters = "              $filter_fld
                                $filter_key
                                $filter_trash";
   return $filters;
}

sub _select_files
{
   my $filters = _build_filters();
   my $files = $db->SelectARef(
      "SELECT f.*, DATE(f.file_created) as created, 
                                (SELECT COUNT(*) FROM Comments WHERE cmt_type=1 AND file_id=cmt_ext_id) as comments,
                                DATE(file_created) AS file_date,
                                UNIX_TIMESTAMP(file_trashed) as trashed_at
                                FROM Files f 
                                WHERE f.usr_id=? 
                                $filters
                                " . XUtils::makeSortSQLcode( $f, 'file_created' ) . $ses->makePagingSQLSuffix( $f->{page} ),
      $ses->getUserId
   );

   my $current_time = $db->SelectOne("SELECT UNIX_TIMESTAMP()");

   for (@$files)
   {
      $_->{site_url}  = $c->{site_url};
      $_->{file_size} = $ses->makeFileSize( $_->{file_size} );
      my $file_descr = $_->{file_descr};
      utf8::decode($file_descr);
      $_->{file_descr} = length($file_descr) > 48 ? substr( $file_descr, 0, 48 ) . '&#133;' : $file_descr;
      utf8::encode( $_->{file_descr} );
      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} = shorten( $file_name, $c->{display_max_filename} );
      utf8::encode( $_->{file_name_txt} );
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{file_downloads} ||= '';
      $_->{comments}       ||= '';
      $_->{time_left} = timediff( $current_time, $_->{trashed_at} + $c->{trash_expire} * 3600 )
        if $_->{trashed_at};
      $_->{file_vip} = $_->{file_price} > 0;
   }

   sub timediff
   {
      my $interval = $_[1] - $_[0];
      return int( $interval / 3600 ) . " hours" if $interval > 3600;
      return int( $interval / 60 ) . " minutes" if $interval > 60;
      return $interval . " seconds";
   }

   return $files;
}

sub _select_files_total
{
   my $filters = _build_filters();
   $db->SelectOne(
      "SELECT COUNT(*) FROM Files f
                                WHERE usr_id=?
                                $filters",
      $ses->getUserId
   );
}

sub _select_folders
{
   my $filter_trashed_folder = "AND fld_trashed" . ( $f->{fld_id} == -1 ? " > 0" : " = 0" );

   my $folders = $db->SelectARef(
      "SELECT f.*, COUNT(ff.file_id) as files_num
                                  FROM Folders f
                                  LEFT JOIN Files ff ON f.fld_id=ff.file_fld_id
                                  WHERE f.usr_id=? 
                                  AND fld_parent_id=?
                                  $filter_trashed_folder
                                  GROUP BY fld_id
                                  ORDER BY fld_name" . $ses->makePagingSQLSuffix( $f->{page} ), $ses->getUserId, $f->{fld_id}
   );

   my $fldRegistry = $ses->require("Engine::Components::FoldersRegistry");

   for (@$folders)
   {
      $_->{fld_name_txt} = length( $_->{fld_name} ) > 25 ? substr( $_->{fld_name}, 0, 25 ) . '&#133;' : $_->{fld_name};
      $_->{files_total} = sum(map { _files_count($_) } $fldRegistry->findChildren($_));
   }

   return $folders;
}

sub _select_folders_total
{
   my $filter_trashed_folder = "AND fld_trashed" . ( $f->{fld_id} == -1 ? " > 0" : " = 0" );

   $db->SelectOne(
      "SELECT COUNT(*) FROM Folders f
                                WHERE usr_id=?
                                AND f.fld_parent_id=?
                                $filter_trashed_folder
                                ",
      $ses->getUserId,
      $f->{fld_id} || 0
   );
}

sub _files_count
{
   my ($fld) = @_;
   $db->SelectOne("SELECT COUNT(*) FROM Files WHERE file_fld_id=? AND !file_trashed", $fld->{fld_id});
}

1;
