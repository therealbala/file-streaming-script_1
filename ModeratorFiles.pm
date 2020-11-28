package Engine::Actions::ModeratorFiles;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(del_selected)] );

use XUtils;

sub main
{
   return $ses->message($ses->{lang}->{lang_access_denied})
     if !$ses->getUser->{usr_adm} && !( $c->{m_d} && $ses->getUser->{usr_mod} && $c->{m_d_f} );

   my $filter_files;
   if ( $f->{mass_search} )
   {
      my @arr;
      push @arr, $1 while $f->{mass_search} =~ /\/(\w{12})\//gs;
      $filter_files = "AND file_code IN ('" . join( "','", @arr ) . "')";
   }

   $f->{per_page} ||= $c->{items_per_page};
   $f->{usr_id} = $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_login=?", $f->{usr_login} ) if $f->{usr_login};
   my $filter_key  = "AND (file_name LIKE '%$f->{key}%' OR file_code='$f->{key}')" if $f->{key};
   my $filter_user = "AND f.usr_id='$f->{usr_id}'"                                 if $f->{usr_id};
   my $filter_ip   = "AND f.file_ip='$f->{ip}'"                         if $f->{ip} =~ /^[\d\.]+$/;
   my $files = $db->SelectARef(
      "SELECT f.*,
                                       file_ip as file_ip,
                                       u.usr_id, u.usr_login
                                FROM Files f
                                LEFT JOIN Users u ON f.usr_id = u.usr_id
                                WHERE 1
                                $filter_files
                                $filter_key
                                $filter_user
                                $filter_ip
                                ORDER BY file_created DESC
                                " . $ses->makePagingSQLSuffix( $f->{page}, $f->{per_page} )
   );
   my $total = $db->SelectOne(
      "SELECT COUNT(*) as total_count
                                FROM Files f 
                                WHERE 1 
                                $filter_files
                                $filter_key 
                                $filter_user 
                                $filter_ip
                                "
   );

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
      $_->{file_size2} = sprintf( "%.01f Mb", $_->{file_size} / 1048576 );
      $_->{download_link} = $ses->makeFileLink($_);
   }

   $ses->PrintTemplate(
      "admin_files_moderator.html",
      'files'              => $files,
      'key'                => $f->{key},
      'usr_id'             => $f->{usr_id},
      "per_$f->{per_page}" => ' checked',
      'paging'             => $ses->makePagingLinks( $f, $total ),
      'items_per_page'     => $c->{items_per_page},
      'usr_login'          => $f->{usr_login},
      'token'              => $ses->genToken,
   );
}

sub del_selected
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
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
   return $ses->redirect("$c->{site_url}/?op=moderator_files");
}

1;
